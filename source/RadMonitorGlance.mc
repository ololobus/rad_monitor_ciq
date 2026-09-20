using Toybox.WatchUi;
using Toybox.Timer;
using Toybox.Graphics as G;

(:glance)
class RadMonitorGlance extends WatchUi.GlanceView {
    var _timer;
    function initialize() { GlanceView.initialize(); }
    function onShow() {
        _timer=new Timer.Timer(); _timer.start(method(:refresh),30000,true);
    }
    function refresh() as Void { WatchUi.requestUpdate(); }
    function onHide() { if (_timer!=null) { _timer.stop(); _timer=null; } }
    function fit(dc,x,y,value,width,font,justify) {
        var out=value;
        while(out.length()>0 && dc.getTextWidthInPixels(out,font)>width) {
            out=out.substring(0,out.length()-1);
        }
        dc.drawText(x,y,font,out,justify);
    }
    function rate(value) {
        if(value<10) { return value.format("%.3f"); }
        if(value<100) { return value.format("%.2f"); }
        if(value<1000) { return value.format("%.1f"); }
        return value.format("%.0f");
    }
    function count(value) {
        if(value<1000) { return value.format("%.1f"); }
        if(value<10000) { return value.format("%.0f"); }
        if(value<1000000) { return (value/1000.0).format("%.1f")+"k"; }
        return (value/1000000.0).format("%.1f")+"M";
    }
    function battery(value) {
        if(value==null) { return "--%"; }
        if(value>99) { value=99; }
        return value.toNumber().format("%d")+"%";
    }
    function onUpdate(dc) {
        dc.setColor(G.COLOR_WHITE,G.COLOR_BLACK); dc.clear();
        var sample=MeasurementStore.load();
        var status=MeasurementStore.loadStatus();
        var font=G.FONT_XTINY;
        var dose=sample==null ? "--" : rate(sample["dose"]);
        var cps=sample==null ? "--" : count(sample["cps"]);
        var charge=battery(status==null || !status.hasKey("battery") ? null : status["battery"]);
        var left=4; var right=dc.getWidth()-4;
        fit(dc,left,0,"RADMONITOR",156,font,G.TEXT_JUSTIFY_LEFT);
        fit(dc,left,20,dose+" µSv/h",156,font,G.TEXT_JUSTIFY_LEFT);
        fit(dc,left,40,cps+" CPS",108,font,G.TEXT_JUSTIFY_LEFT);
        fit(dc,right,40,charge,44,font,G.TEXT_JUSTIFY_RIGHT);
    }
}
