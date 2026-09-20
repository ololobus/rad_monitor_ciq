using Toybox.Application;
using Toybox.Lang;
using Toybox.System;

// 360 ten-second recording bins = one recorded hour. Pauses consume no bins;
// their marker is retained for cache compatibility, while the plot connects the
// retained measurements continuously. Records are [epoch:u32, mean:float, break:u32].
class HistoryStore {
    const KEY="history-v1";
    const CAPACITY=360;
    var points as Lang.Array<Lang.Array> = [];
    var _lastTick=null; var _elapsed=0; var _sum=0.0; var _count=0;
    var dirty=false;
    function initialize(loadSaved) {
        if(!loadSaved) { return; }
        try {
            var bytes=Application.Storage.getValue(KEY);
            if(bytes instanceof Lang.ByteArray && bytes.size()%12==0 && bytes.size()<=CAPACITY*12) {
                for(var p=0;p<bytes.size();p+=12) {
                    var dose=RadiacodeProtocol.f32(bytes,p+4);
                    if(!(dose>=0 && dose<3.4e38)) { points=[]; return; }
                    points.add([RadiacodeProtocol.u32(bytes,p).toNumber(),dose,RadiacodeProtocol.u32(bytes,p+8).toNumber()]);
                }
            }
        } catch(e) { System.println("RC history load: "+e.getErrorMessage()); }
    }
    function pause() { _lastTick=null; _elapsed=0; _count=0; _sum=0.0; }
    function add(timestamp,dose,tick) {
        if(_lastTick==null || tick<_lastTick || tick-_lastTick>15000) {
            pause();
            if(points.size()==CAPACITY) { points=points.slice(1,null); }
            points.add([timestamp,dose,1]);
            _lastTick=tick; _sum=dose; _count=1; dirty=true; return;
        }
        _elapsed+=tick-_lastTick; _lastTick=tick;
        if(_elapsed>=10000) {
            _elapsed-=10000; _sum=0.0; _count=0;
            if(points.size()==CAPACITY) { points=points.slice(1,null); }
            points.add([timestamp,dose,0]);
        }
        _sum+=dose; _count++;
        var last=points[points.size()-1]; last[0]=timestamp; last[1]=_sum/_count;
        dirty=true;
    }
    function save() {
        if(!dirty) { return; }
        try {
            var bytes=[]b;
            for(var i=0;i<points.size();i++) {
                var item=points[i]; var record=new [12]b;
                record.encodeNumber(item[0],Lang.NUMBER_FORMAT_UINT32,{:offset=>0,:endianness=>Lang.ENDIAN_LITTLE});
                record.encodeNumber(item[1],Lang.NUMBER_FORMAT_FLOAT,{:offset=>4,:endianness=>Lang.ENDIAN_LITTLE});
                record.encodeNumber(item[2],Lang.NUMBER_FORMAT_UINT32,{:offset=>8,:endianness=>Lang.ENDIAN_LITTLE});
                bytes.addAll(record);
            }
            Application.Storage.setValue(KEY,bytes); dirty=false;
        } catch(e) { System.println("RC history save: "+e.getErrorMessage()); }
    }
}
