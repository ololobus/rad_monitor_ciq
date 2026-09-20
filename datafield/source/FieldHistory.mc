using Toybox.Lang;

// One hour of ten-second means for both display modes. A packed byte array
// avoids hundreds of heap-allocated arrays on 32 KiB data-field devices.
class FieldHistory {
    const CAPACITY=360;
    const STRIDE=8;
    var _data as Lang.ByteArray=new [CAPACITY*STRIDE]b;
    var _next=0; var count=0;
    var _lastTick=null; var _elapsed=0;
    var _doseSum=0.0; var _cpsSum=0.0; var _samples=0;

    function pause() {
        _lastTick=null; _elapsed=0; _doseSum=0.0; _cpsSum=0.0; _samples=0;
    }
    function add(dose,cps,tick) {
        if(_lastTick==null || tick<_lastTick || tick-_lastTick>15000) {
            pause(); _lastTick=tick; _doseSum=dose; _cpsSum=cps; _samples=1;
            append(dose,cps); return;
        }
        _elapsed+=tick-_lastTick; _lastTick=tick;
        if(_elapsed>=10000) {
            _elapsed-=10000; _doseSum=0.0; _cpsSum=0.0; _samples=0;
            append(dose,cps);
        }
        _doseSum+=dose; _cpsSum+=cps; _samples++;
        write((_next+CAPACITY-1)%CAPACITY,_doseSum/_samples,_cpsSum/_samples);
    }
    function append(dose,cps) {
        write(_next,dose,cps); _next=(_next+1)%CAPACITY;
        if(count<CAPACITY) { count++; }
    }
    function write(index,dose,cps) {
        var offset=index*STRIDE;
        _data.encodeNumber(dose,Lang.NUMBER_FORMAT_FLOAT,
            {:offset=>offset,:endianness=>Lang.ENDIAN_LITTLE});
        _data.encodeNumber(cps,Lang.NUMBER_FORMAT_FLOAT,
            {:offset=>offset+4,:endianness=>Lang.ENDIAN_LITTLE});
    }
    function value(index,showCps) {
        var first=count==CAPACITY ? _next : 0;
        var physical=(first+index)%CAPACITY;
        return _data.decodeNumber(Lang.NUMBER_FORMAT_FLOAT,
            {:offset=>physical*STRIDE+(showCps ? 4 : 0),:endianness=>Lang.ENDIAN_LITTLE});
    }
}
