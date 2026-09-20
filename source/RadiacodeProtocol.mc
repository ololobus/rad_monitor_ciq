using Toybox.Lang;

// Minimal MIT-licensed cdump/radiacode port. No BLE or UI dependencies.
// Reference: radiacode.py execute/read_request; decoders/databuf.py.
module RadiacodeProtocol {
    function u16(b as Lang.ByteArray, p as Lang.Number) { return b.decodeNumber(Lang.NUMBER_FORMAT_UINT16, {:offset=>p, :endianness=>Lang.ENDIAN_LITTLE}).toNumber(); }
    function u32(b as Lang.ByteArray, p as Lang.Number) { return b.decodeNumber(Lang.NUMBER_FORMAT_UINT32, {:offset=>p, :endianness=>Lang.ENDIAN_LITTLE}); }
    function i32(b as Lang.ByteArray, p as Lang.Number) { return b.decodeNumber(Lang.NUMBER_FORMAT_SINT32, {:offset=>p, :endianness=>Lang.ENDIAN_LITTLE}); }
    function f32(b as Lang.ByteArray, p as Lang.Number) { return b.decodeNumber(Lang.NUMBER_FORMAT_FLOAT, {:offset=>p, :endianness=>Lang.ENDIAN_LITTLE}); }
    function word(n) {
        var b = new [4]b;
        b.encodeNumber(n, Lang.NUMBER_FORMAT_UINT32, {:endianness=>Lang.ENDIAN_LITTLE});
        return b;
    }
    function require(ok, message) {
        if (!ok) { throw new Lang.InvalidValueException(message); }
    }
    function sizeWithOptionalZero(b as Lang.ByteArray, declaredEnd) {
        return b.size()==declaredEnd || (b.size()==declaredEnd+1 && b[declaredEnd]==0);
    }
    function request(command, sequence, args) as Lang.ByteArray {
        var b = word(4 + args.size());
        b.add(command & 255); b.add((command >> 8) & 255);
        b.add(0); b.add(0x80 + (sequence % 32)); b.addAll(args);
        return b;
    }
    function checkHeader(b as Lang.ByteArray, command, sequence) {
        require(b.size() >= 4, "Short reply");
        require(u16(b,0) == command && b[2] == 0 && b[3] == 0x80 + sequence, "Reply sequence");
    }
    function firmware(b as Lang.ByteArray) {
        // <HH> boot version, length-prefixed boot string, <HH> target version/string.
        require(b.size() >= 9, "Short version");
        var p = 9 + b[8];
        require(p + 5 <= b.size(), "Version length");
        var minor = u16(b,p); var major = u16(b,p+2);
        require(p + 5 + b[p+4] == b.size(), "Version tail");
        require(major > 4 || (major == 4 && minor >= 8), "Need FW >=4.8");
        return major.format("%d") + "." + minor.format("%d");
    }
    function dataBuffer(b as Lang.ByteArray, baseTime) as Lang.Dictionary or Null {
        return decodeDataBuffer(b,baseTime,null);
    }
    function decodeDataBuffer(b as Lang.ByteArray, baseTime, diagnostics as Lang.Dictionary or Null) as Lang.Dictionary or Null {
        require(b.size() >= 12 && u32(b,4) == 1, "DATA_BUF status");
        var declaredSize = u32(b,8);
        require(declaredSize <= RadiacodeConstants.MAX_RESPONSE - 12, "DATA_BUF size");
        var size = declaredSize.toNumber();
        var end = 12 + size;
        // Match upstream's single trailing zero workaround for newer firmware.
        require(sizeWithOptionalZero(b,end), "DATA_BUF length");
        var p = 12; var nextSeq = null; var latest = null; var rare = null;
        var doseTime=null; var doseDelta=0.0;
        if(diagnostics!=null && diagnostics.hasKey("doseBaseTime")) {
            doseTime=diagnostics["doseBaseTime"];
        }
        var sizes = [15,8,16,14,16,16,6,4,6,6];
        while (p < end) {
            require(p + 7 <= end, "Record header");
            var seq=b[p]; var eid=b[p+1]; var gid=b[p+2];
            // Exchange filtering can omit records while the device's sequence
            // counter still advances. Record the gap, but keep parsing from the
            // already validated header so later RareData is not discarded.
            if (nextSeq != null && seq != nextSeq) {
                if (diagnostics != null && !diagnostics.hasKey("expected")) {
                    diagnostics["expected"]=nextSeq; diagnostics["actual"]=seq;
                    diagnostics["offset"]=p-12; diagnostics["remaining"]=end-p;
                    diagnostics["eid"]=eid; diagnostics["gid"]=gid;
                }
            }
            nextSeq = (seq + 1) % 256;
            var timestamp = baseTime + (i32(b,p+3) / 100);
            p += 7;
            var length = 0;
            if (eid == 0 && gid < sizes.size()) {
                length = sizes[gid];
            } else if (eid == 1 && gid >= 1 && gid <= 3) {
                require(p+6 <= end, "Batch header");
                var stride = [8,16,14][gid-1];
                length = 6 + u16(b,p) * stride;
            } else {
                throw new Lang.InvalidValueException("Record " + eid + "/" + gid);
            }
            require(p+length <= end, "Truncated record");
            var recordDose=null;
            if (eid == 0 && gid == 0) {
                var cps=f32(b,p); var rawDose=f32(b,p+4);
                // Reject NaN, infinity and negative measurements; keep real zeros.
                require(cps >= 0 && cps < 3.4e38 && rawDose >= 0 && rawDose < 3.4e34, "Invalid sample");
                var sample={"cps"=>cps, "dose"=>rawDose*10000.0, "rawDose"=>rawDose,
                    "doseError"=>u16(b,p+10)/10.0, "cpsError"=>u16(b,p+8)/10.0,
                    "timestamp"=>timestamp, "flags"=>u16(b,p+12), "rtFlags"=>b[p+14]};
                if (latest == null || timestamp >= (latest as Lang.Dictionary)["timestamp"]) { latest=sample; }
                recordDose=sample["dose"];
            }
            if(eid==0 && gid==2) {
                var storedRawDose=f32(b,p+8);
                require(storedRawDose>=0 && storedRawDose<3.4e34,"Invalid stored dose rate");
                recordDose=storedRawDose*10000.0;
            }
            if (eid == 0 && gid == 3) {
                // Upstream RareData <IfHHH>: duration, dose, temperature, battery, flags.
                var accumulated=f32(b,p+4); var battery=u16(b,p+10)/100.0;
                require(accumulated>=0 && accumulated<3.4e34, "Invalid total dose");
                require(battery>=0 && battery<=100, "Invalid battery");
                var status={"timestamp"=>timestamp, "duration"=>u32(b,p),
                    "rawAccumulated"=>accumulated, "accumulated"=>accumulated*10000.0,
                    "temperature"=>(u16(b,p+8)-2000)/100.0, "battery"=>battery,
                    "flags"=>u16(b,p+12)};
                if(rare==null || timestamp>=(rare as Lang.Dictionary)["timestamp"]) { rare=status; }
                if(diagnostics!=null && (doseTime==null || timestamp>=doseTime)) {
                    doseTime=timestamp; doseDelta=0.0;
                }
            }
            if(eid==0 && gid==7 && p<end && b[p]==4 && diagnostics!=null) {
                // EventId.DOSE_RESET. This is authoritative even when the
                // infrequent RareData status has not arrived yet.
                diagnostics["doseReset"]=timestamp;
                if(doseTime==null || timestamp>=doseTime) { doseTime=timestamp; doseDelta=0.0; }
            }
            if(eid==0 && gid==7 && p<end && b[p]<=2 && diagnostics!=null &&
                (doseTime==null || timestamp>=doseTime)) {
                // Power-off/on and low-battery shutdown delimit recording. Keep
                // the dose already accumulated, but never integrate across it.
                doseTime=timestamp;
            }
            if(recordDose!=null && diagnostics!=null && (doseTime==null || timestamp>doseTime)) {
                if(doseTime!=null) {
                    var doseSeconds=timestamp-doseTime;
                    // Detector history is normally dense. Never bridge a power-off,
                    // deleted-log or malformed multi-minute hole with a dose rate.
                    if(doseSeconds<=300) { doseDelta+=recordDose*doseSeconds/3600.0; }
                }
                doseTime=timestamp;
            }
            p += length;
        }
        if(diagnostics!=null) {
            if(rare!=null) { diagnostics["rare"]=rare; }
            if(doseTime!=null) {
                diagnostics["doseUntil"]=doseTime;
                diagnostics["doseDelta"]=doseDelta;
            }
        }
        return latest;
    }
}

// Length prefix can itself be fragmented. Bounded allocation, one reply per request.
class RadiacodeFrame {
    var _prefix; var _body; var _expected;
    function initialize() { reset(); }
    function reset() { _prefix=[]b; _body=[]b; _expected=null; }
    function feed(bytes as Lang.ByteArray) as Lang.ByteArray or Null {
        var p=0;
        while (_prefix.size()<4 && p<bytes.size()) { _prefix.add(bytes[p]); p++; }
        if (_prefix.size()<4) { return null; }
        if (_expected == null) {
            _expected=RadiacodeProtocol.u32(_prefix,0);
            RadiacodeProtocol.require(_expected >= 4 && _expected <= RadiacodeConstants.MAX_RESPONSE, "Reply too large");
        }
        RadiacodeProtocol.require(_body.size()+bytes.size()-p <= _expected, "Reply overflow");
        for (;p<bytes.size();p++) { _body.add(bytes[p]); }
        return _body.size() == _expected ? _body : null;
    }
}
