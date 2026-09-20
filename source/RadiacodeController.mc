using Toybox.Time;
using Toybox.Lang;
using Toybox.Time.Gregorian;
using Toybox.System;
using Toybox.Timer;
using Toybox.WatchUi;

class RadiacodeController {
    var transport; var sample as Lang.Dictionary or Null; var detail="Starting"; var firmware="";
    var deviceStatus as Lang.Dictionary or Null;
    var recordGaps=0; var history as HistoryStore;
    var _timer; var _running=false; var _frame; var _sequence=0; var _command; var _pending=false;
    var _reply; var _writeDone=false; var _step=0; var _deadline=0; var _pollAt=0;
    var _retryAt=0; var _retries=0; var _baseTime=0; var _savedAt=0; var _statusPollAt=0; var _readTarget=0;
    // Dose read compatibility: 0 generic, 1 typed batch, 2 legacy single VSFR,
    // 3 unavailable (reconstruct from detector-buffered records).
    var _directDoseAt=0; var _doseMode=0;
    function initialize() {
        transport=new RadiacodeBleTransport(self); _frame=new RadiacodeFrame();
        sample=MeasurementStore.load(); deviceStatus=MeasurementStore.loadStatus(); history=new HistoryStore(true);
    }
    function acceptStatus(candidate as Lang.Dictionary,now) {
        var sourceTime=candidate["timestamp"];
        if(sourceTime>now+5) { return false; }
        if(deviceStatus!=null && deviceStatus.hasKey("resetSourceTimestamp") &&
            sourceTime<=deviceStatus["resetSourceTimestamp"]) { return false; }
        // RareData can be hours old when draining the detector buffer. Its dose
        // duration is monotonic between resets and is a better freshness key than
        // the rebased packet timestamp, especially across app sessions.
        if(deviceStatus!=null) {
            var oldDuration=deviceStatus["duration"];
            var newDuration=candidate["duration"];
            var oldSource=deviceStatus.hasKey("sourceTimestamp") ? deviceStatus["sourceTimestamp"] : deviceStatus["timestamp"];
            if((newDuration<oldDuration && sourceTime<=oldSource) ||
                (newDuration==oldDuration && sourceTime<oldSource)) { return false; }
        }
        // A direct DS_uR read is newer than buffered RareData being drained in
        // the following DATA_BUF polls. Keep that exact detector total while
        // still accepting battery and duration from the status record.
        if(deviceStatus!=null && _directDoseAt>0) {
            candidate["accumulated"]=deviceStatus["accumulated"];
            candidate["rawAccumulated"]=deviceStatus["rawAccumulated"];
        }
        candidate["sourceTimestamp"]=sourceTime;
        candidate["doseIntegratedUntil"]=_directDoseAt>0 ? _directDoseAt : sourceTime;
        candidate["timestamp"]=now;
        deviceStatus=candidate; return true;
    }
    function acceptDirectDose(raw,now) {
        // DS_uR is the detector's current accumulated dose in micro-roentgen.
        // The detector uses 100 µR per µSv when configured for sieverts.
        var accumulated=raw/100.0;
        if(accumulated<0 || accumulated>=3.4e34) { return false; }
        if(deviceStatus==null) {
            deviceStatus={"accumulated"=>accumulated,"rawAccumulated"=>accumulated/10000.0,
                "duration"=>-1,"timestamp"=>now};
        } else {
            deviceStatus["accumulated"]=accumulated;
            deviceStatus["rawAccumulated"]=accumulated/10000.0;
            deviceStatus["duration"]=-1;
            deviceStatus["timestamp"]=now;
        }
        _directDoseAt=now;
        deviceStatus["doseIntegratedUntil"]=now;
        MeasurementStore.saveStatus(deviceStatus);
        return true;
    }
    function resetDose(sourceTime,now) {
        var reset={"accumulated"=>0.0,"rawAccumulated"=>0.0,"duration"=>0,
            "timestamp"=>now,"sourceTimestamp"=>sourceTime,
            "resetSourceTimestamp"=>sourceTime,"doseIntegratedUntil"=>sourceTime};
        if(deviceStatus!=null && deviceStatus.hasKey("battery")) {
            reset["battery"]=deviceStatus["battery"];
        }
        _directDoseAt=0; deviceStatus=reset; MeasurementStore.saveStatus(deviceStatus);
        System.println("RC accumulated dose reset");
    }
    function start() {
        _running=true; _timer=new Timer.Timer();
        _timer.start(method(:tick),2000,true); transport.start();
    }
    function stop() {
        _running=false;
        if (_timer!=null) { _timer.stop(); }
        transport.stop(); history.save();
        if (sample!=null) { MeasurementStore.save(sample); }
        if(deviceStatus!=null) { MeasurementStore.saveStatus(deviceStatus); }
    }
    function onTransportState(state) {
        detail=state; _deadline=System.getTimer()+(state.equals("SCANNING") ? 20000 : 12000);
        System.println("RC state=" + state); WatchUi.requestUpdate();
    }
    function onTransportError(message) {
        _pending=false; _reply=null; _readTarget=0; _directDoseAt=0; _frame.reset(); detail=message; history.pause();
        var delay=[5000,10000,20000,30000][_retries<4 ? _retries : 3];
        _retries++; _retryAt=System.getTimer()+delay;
        System.println("RC error=" + message + " retry(ms)=" + delay);
    }
    function retry() {
        if (!_running || !transport.state.equals("ERROR")) { return; }
        _retryAt=0;
    }
    function tick() as Void {
        if (!_running) { return; }
        var now=System.getTimer();
        if (transport.state.equals("ERROR")) {
            if (now>=_retryAt) { transport.start(); }
        } else if (_pending && now>=_deadline) {
            transport.fail("Reply timeout " + _command.format("%04x"));
        } else if (transport.state.equals("READY")) {
            if (!_pending && now>=_statusPollAt) {
                _readTarget=RadiacodeConstants.DS_uR;
                if(_doseMode==3) {
                    _readTarget=0; _statusPollAt=now+60000; _pollAt=0;
                } else if(_doseMode==1) {
                    request(RadiacodeConstants.RD_VIRT_SFR_BATCH,
                        RadiacodeProtocol.word(1).addAll(RadiacodeProtocol.word(_readTarget)));
                } else if(_doseMode==2) {
                    request(RadiacodeConstants.RD_VIRT_SFR,RadiacodeProtocol.word(_readTarget));
                } else {
                    request(RadiacodeConstants.RD_VIRT_STRING,RadiacodeProtocol.word(_readTarget));
                }
            } else if (!_pending && now>=_pollAt) {
                _readTarget=RadiacodeConstants.DATA_BUF;
                request(RadiacodeConstants.RD_VIRT_STRING,RadiacodeProtocol.word(_readTarget));
            }
        } else if (now>=_deadline) { transport.fail(transport.state+" timeout"); }
        WatchUi.requestUpdate();
    }
    function onSubscribed() { _step=0; _sequence=0; initializeStep(); }
    function initializeStep() {
        if (_step==0) { request(RadiacodeConstants.SET_EXCHANGE,[1,255,18,255]b); }
        else if (_step==1) {
            var t=Gregorian.info(Time.now(),Time.FORMAT_SHORT);
            request(RadiacodeConstants.SET_TIME,[t.day,t.month as Lang.Number,t.year-2000,0,t.sec,t.min,t.hour,0]b);
        } else if (_step==2) {
            request(RadiacodeConstants.WR_VIRT_SFR,RadiacodeProtocol.word(RadiacodeConstants.DEVICE_TIME).addAll([0,0,0,0]b));
        } else if (_step==3) { request(RadiacodeConstants.GET_VERSION,[]b); }
        else { transport.ready(); _pollAt=0; }
    }
    function request(command,args) {
        try {
            _command=command; _pending=true; _reply=null; _writeDone=false; _frame.reset();
            _deadline=System.getTimer()+10000;
            System.println("RC tx=" + command.format("%04x") + " seq=" + _sequence);
            transport.send(RadiacodeProtocol.request(command,_sequence,args));
        } catch(e) { transport.fail("Request: " + e.getErrorMessage()); }
    }
    function onWriteComplete() { _writeDone=true; complete(); }
    function advanceBufferedDose(delta,until,now) {
        if(deviceStatus==null) { return false; }
        var status=deviceStatus as Lang.Dictionary;
        var base=null;
        if(status.hasKey("doseIntegratedUntil")) { base=status["doseIntegratedUntil"]; }
        else if(status.hasKey("sourceTimestamp")) { base=status["sourceTimestamp"]; }
        if(base==null || until<=base) { return false; }
        status["accumulated"]+=delta;
        status["rawAccumulated"]=status["accumulated"]/10000.0;
        if(status.hasKey("duration") && status["duration"]>=0) { status["duration"]+=until-base; }
        status["doseIntegratedUntil"]=until;
        status["timestamp"]=now;
        detail="Dose buffered "+status["accumulated"].format("%.3f")+" uSv";
        return true;
    }
    function onBytes(bytes) {
        if (!_pending) { transport.fail("Unexpected notify"); return; }
        try { _reply=_frame.feed(bytes); complete(); }
        catch(e) { transport.fail("Protocol: " + e.getErrorMessage()); }
    }
    function complete() {
        if (!_pending || !_writeDone || _reply==null) { return; }
        try {
            RadiacodeProtocol.checkHeader(_reply,_command,_sequence);
            _sequence=(_sequence+1)%32;
            var reply=_reply; _reply=null; _pending=false; _frame.reset();
            if (_command==RadiacodeConstants.WR_VIRT_SFR) {
                RadiacodeProtocol.require(reply.size()==8 && RadiacodeProtocol.u32(reply,4)==1,"Device time status");
                _baseTime=Time.now().value()+128;
            }
            if (_command==RadiacodeConstants.GET_VERSION) {
                firmware=RadiacodeProtocol.firmware(reply); System.println("RC firmware="+firmware);
            }
            if (_command==RadiacodeConstants.RD_VIRT_STRING && _readTarget==RadiacodeConstants.DS_uR) {
                // Generic virtual-register reads are supported by Radiacode 102
                // firmware and return: result, byte count, then register bytes.
                // Some current firmware appends one zero byte after the declared
                // value. Match upstream read_request's compatibility workaround.
                var directLengthOk=RadiacodeProtocol.sizeWithOptionalZero(reply,16);
                if(directLengthOk && RadiacodeProtocol.u32(reply,4)==1 &&
                    RadiacodeProtocol.u32(reply,8)==4) {
                    var rawDose=RadiacodeProtocol.u32(reply,12);
                    if(acceptDirectDose(rawDose,Time.now().value())) {
                        detail="Dose raw "+rawDose.format("%d")+" uR (generic)";
                        System.println("RC direct accumulated="+deviceStatus["accumulated"]+" raw_uR="+rawDose);
                    }
                    _readTarget=0;
                    _statusPollAt=System.getTimer()+60000; _pollAt=0;
                } else {
                    // Some 10x firmware rejects generic reads for VSFRs. Retry
                    // with the dedicated typed batch command used upstream.
                    detail="Dose generic unavailable; trying batch";
                    System.println("RC generic dose unavailable; trying batch");
                    _doseMode=1;
                    request(RadiacodeConstants.RD_VIRT_SFR_BATCH,
                        RadiacodeProtocol.word(1).addAll(RadiacodeProtocol.word(RadiacodeConstants.DS_uR)));
                }
            } else if (_command==RadiacodeConstants.RD_VIRT_SFR_BATCH && _readTarget==RadiacodeConstants.DS_uR) {
                var batchLengthOk=RadiacodeProtocol.sizeWithOptionalZero(reply,12);
                if(batchLengthOk && RadiacodeProtocol.u32(reply,4)==1) {
                    var batchDose=RadiacodeProtocol.u32(reply,8);
                    if(acceptDirectDose(batchDose,Time.now().value())) {
                        detail="Dose raw "+batchDose.format("%d")+" uR (batch)";
                        System.println("RC batch accumulated="+deviceStatus["accumulated"]+" raw_uR="+batchDose);
                    }
                    _readTarget=0;
                    _statusPollAt=System.getTimer()+60000; _pollAt=0;
                } else {
                    var flags=reply.size()>=8 ? RadiacodeProtocol.u32(reply,4) : -1;
                    detail="Dose batch unavailable; trying single";
                    System.println("RC batch dose unavailable flags="+flags+" size="+reply.size()+"; trying single");
                    _doseMode=2;
                    request(RadiacodeConstants.RD_VIRT_SFR,RadiacodeProtocol.word(RadiacodeConstants.DS_uR));
                }
            } else if (_command==RadiacodeConstants.RD_VIRT_SFR && _readTarget==RadiacodeConstants.DS_uR) {
                var singleDose=null;
                if(RadiacodeProtocol.sizeWithOptionalZero(reply,12) &&
                    RadiacodeProtocol.u32(reply,4)==1) {
                    singleDose=RadiacodeProtocol.u32(reply,8);
                } else if(RadiacodeProtocol.sizeWithOptionalZero(reply,16) &&
                    RadiacodeProtocol.u32(reply,4)==1 && RadiacodeProtocol.u32(reply,8)==4) {
                    singleDose=RadiacodeProtocol.u32(reply,12);
                }
                if(singleDose!=null && acceptDirectDose(singleDose,Time.now().value())) {
                    detail="Dose raw "+singleDose.format("%d")+" uR (single)";
                    System.println("RC single accumulated="+deviceStatus["accumulated"]+" raw_uR="+singleDose);
                } else {
                    var first=reply.size()>=8 ? RadiacodeProtocol.u32(reply,4) : -1;
                    var second=reply.size()>=12 ? RadiacodeProtocol.u32(reply,8) : -1;
                    detail="Dose unavailable S"+reply.size().format("%d")+" A"+first.format("%d")+" B"+second.format("%d");
                    System.println("RC single dose unavailable size="+reply.size()+" a="+first+" b="+second);
                    _doseMode=3;
                    // Builds that interpreted a lone zero status as dose saved a
                    // synthetic direct value with unknown duration. Discard it so
                    // the next RareData record can establish a real anchor.
                    if(deviceStatus!=null && deviceStatus.hasKey("duration") && deviceStatus["duration"]<0) {
                        deviceStatus=null; MeasurementStore.saveStatus(null);
                    }
                }
                _readTarget=0;
                _statusPollAt=System.getTimer()+60000; _pollAt=0;
            } else if (_command==RadiacodeConstants.RD_VIRT_STRING) {
                var diagnostics={};
                if(deviceStatus!=null) {
                    if(deviceStatus.hasKey("doseIntegratedUntil")) {
                        diagnostics["doseBaseTime"]=deviceStatus["doseIntegratedUntil"];
                    } else if(deviceStatus.hasKey("sourceTimestamp")) {
                        diagnostics["doseBaseTime"]=deviceStatus["sourceTimestamp"];
                    }
                }
                var fresh=RadiacodeProtocol.decodeDataBuffer(reply,_baseTime,diagnostics);
                if (diagnostics.hasKey("expected")) {
                    recordGaps++;
                    detail="Record gap " + diagnostics["expected"] + ">" + diagnostics["actual"];
                    System.println("RC record gap: expected="+diagnostics["expected"]+
                        " actual="+diagnostics["actual"]+" offset="+diagnostics["offset"]+
                        " remaining="+diagnostics["remaining"]+" eid="+diagnostics["eid"]+
                        " gid="+diagnostics["gid"]+" total="+recordGaps);
                }
                var statusChanged=diagnostics.hasKey("rare");
                if(statusChanged) {
                    var candidate=diagnostics["rare"] as Lang.Dictionary;
                    statusChanged=acceptStatus(candidate,Time.now().value());
                    if(!statusChanged) { System.println("RC ignored historical status timestamp="+candidate["timestamp"]); }
                }
                if(statusChanged) {
                    System.println("RC battery="+deviceStatus["battery"]+" accumulated="+deviceStatus["accumulated"]+
                        " rawTotal="+deviceStatus["rawAccumulated"]+" duration="+deviceStatus["duration"]);
                    // RareData may arrive without RealTimeData. Persist it independently.
                    MeasurementStore.saveStatus(deviceStatus);
                }
                if(diagnostics.hasKey("doseReset")) {
                    var resetTime=diagnostics["doseReset"];
                    var rareTime=null;
                    if(diagnostics.hasKey("rare")) {
                        var resetRare=diagnostics["rare"] as Lang.Dictionary;
                        rareTime=resetRare["timestamp"];
                    }
                    if(rareTime==null || resetTime>=rareTime) { resetDose(resetTime,Time.now().value()); }
                }
                if(diagnostics.hasKey("doseUntil") && diagnostics.hasKey("doseDelta")) {
                    if(advanceBufferedDose(diagnostics["doseDelta"],diagnostics["doseUntil"],Time.now().value())) {
                        MeasurementStore.saveStatus(deviceStatus);
                    }
                }
                if (fresh!=null) {
                    RadiacodeProtocol.require(fresh["timestamp"]<=Time.now().value()+5,"Sample time ahead");
                    sample=fresh; _retries=0;
                    history.add(sample["timestamp"],sample["dose"],System.getTimer());
                    System.println("RC sample uSv/h="+sample["dose"]+" cps="+sample["cps"]+" raw="+sample["rawDose"]+" flags="+sample["flags"]+" rt="+sample["rtFlags"]);
                    if (System.getTimer()-_savedAt>=15000 || _savedAt==0) {
                        MeasurementStore.save(sample); history.save();
                        if(deviceStatus!=null) { MeasurementStore.saveStatus(deviceStatus); }
                        _savedAt=System.getTimer();
                        System.println("RC freeMemory="+System.getSystemStats().freeMemory);
                    }
                }
                _readTarget=0;
                _pollAt=System.getTimer()+2000;
            } else { _step++; initializeStep(); }
            WatchUi.requestUpdate();
        } catch(e) { transport.fail("Protocol: " + e.getErrorMessage()); }
    }
}
