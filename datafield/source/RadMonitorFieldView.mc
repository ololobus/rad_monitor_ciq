using Toybox.Application;
using Toybox.FitContributor;
using Toybox.Graphics as G;
using Toybox.Lang;
using Toybox.System;
using Toybox.WatchUi;

class RadMonitorFieldView extends WatchUi.DataField {
    var _controller as FieldController;
    var _doseField as FitContributor.Field; var _cpsField as FitContributor.Field;
    var _writtenSerial=-1;
    var _timerRunning=false;
    function initialize(controller) {
        DataField.initialize(); _controller=controller;
        _doseField=createField("dose_rate",0,FitContributor.DATA_TYPE_FLOAT,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD,:units=>"uSv/h"});
        _cpsField=createField("count_rate",1,FitContributor.DATA_TYPE_FLOAT,
            {:mesgType=>FitContributor.MESG_TYPE_RECORD,:units=>"CPS"});
    }
    function showCps() {
        try { return Application.Properties.getValue("ShowCps")==true; }
        catch(e) { return false; }
    }
    function compute(info) {
        _controller.tick();
        var sample=_controller.sample;
        if(_timerRunning && sample!=null &&
            _writtenSerial!=_controller.sampleSerial) {
            var fresh=sample as Lang.Dictionary;
            _doseField.setData(fresh["dose"]);
            _cpsField.setData(fresh["cps"]);
            _writtenSerial=_controller.sampleSerial;
        }
        if(sample==null) { return null; }
        var current=sample as Lang.Dictionary;
        return showCps() ? current["cps"] : current["dose"];
    }
    function onTimerStart() { _timerRunning=true; }
    function onTimerResume() { _timerRunning=true; }
    function onTimerPause() { _timerRunning=false; }
    function onTimerStop() { _timerRunning=false; }
    function onTimerReset() { _timerRunning=false; }

    function formatDose(value) {
        if(value<10) { return value.format("%.3f"); }
        if(value<100) { return value.format("%.2f"); }
        if(value<1000) { return value.format("%.1f"); }
        return value.format("%.0f");
    }
    function formatCps(value) {
        if(value<1000) { return value.format("%.1f"); }
        if(value<10000) { return value.format("%.0f"); }
        if(value<1000000) { return (value/1000.0).format("%.1f")+"k"; }
        return (value/1000000.0).format("%.1f")+"M";
    }
    function formatValue(value,cps) { return cps ? formatCps(value) : formatDose(value); }
    function fit(dc,x,y,text,width,font,justify) {
        var out=text;
        while(out.length()>0 && dc.getTextWidthInPixels(out,font)>width) {
            out=out.substring(0,out.length()-1);
        }
        dc.drawText(x,y,font,out,justify);
    }
    function onUpdate(dc) {
        var bg=getBackgroundColor(); var fg=bg==G.COLOR_WHITE ? G.COLOR_BLACK : G.COLOR_WHITE;
        dc.setColor(fg,bg); dc.clear(); dc.setColor(fg,G.COLOR_TRANSPARENT);
        var width=dc.getWidth(); var height=dc.getHeight(); var cps=showCps();
        var pending=_controller.sample;
        if(pending==null) {
            fit(dc,width/2,(height-dc.getFontHeight(G.FONT_XTINY))/2,
                _controller.transport.state,width-6,G.FONT_XTINY,G.TEXT_JUSTIFY_CENTER);
            return;
        }
        var sample=pending as Lang.Dictionary;
        var current=cps ? sample["cps"] : sample["dose"];
        var value=formatValue(current,cps); var unit=cps ? "CPS" : "µSv/h";
        if(width<120 || height<90) {
            fit(dc,width/2,2,value,width-6,G.FONT_SMALL,G.TEXT_JUSTIFY_CENTER);
            fit(dc,width/2,height-dc.getFontHeight(G.FONT_XTINY)-1,unit,
                width-6,G.FONT_XTINY,G.TEXT_JUSTIFY_CENTER); return;
        }
        if(width<150 || height<130) {
            fit(dc,width/2,(height/2)-dc.getFontHeight(G.FONT_SMALL),value,
                width-10,G.FONT_SMALL,G.TEXT_JUSTIFY_CENTER);
            fit(dc,width/2,height/2,unit,width-10,G.FONT_XTINY,G.TEXT_JUSTIFY_CENTER); return;
        }

        var shape=System.getDeviceSettings().screenShape;
        var instinct=shape==System.SCREEN_SHAPE_SEMI_OCTAGON && width==176 && height==176;
        var centerX=instinct ? 55 : width/2;
        fit(dc,centerX,2,value,instinct ? 104 : width-30,G.FONT_SMALL,G.TEXT_JUSTIFY_CENTER);
        fit(dc,centerX,28,unit,instinct ? 104 : width-30,G.FONT_XTINY,G.TEXT_JUSTIFY_CENTER);

        var history=_controller.history;
        if(history.count==0) { return; }
        var minimum=history.value(0,cps); var maximum=minimum;
        for(var i=1;i<history.count;i++) {
            var candidate=history.value(i,cps);
            if(candidate<minimum) { minimum=candidate; }
            if(candidate>maximum) { maximum=candidate; }
        }
        var left=instinct ? 46 : (width*18/100).toNumber();
        var right=instinct ? 168 : (width*82/100).toNumber();
        var top=instinct ? 67 : (height*32/100).toNumber();
        var bottom=(height*80/100).toNumber();
        fit(dc,2,top-8,formatValue(maximum,cps),left-5,G.FONT_XTINY,G.TEXT_JUSTIFY_LEFT);
        fit(dc,2,bottom-dc.getFontHeight(G.FONT_XTINY),formatValue(minimum,cps),
            left-5,G.FONT_XTINY,G.TEXT_JUSTIFY_LEFT);
        dc.drawLine(left,top,left,bottom); dc.drawLine(left,bottom,right,bottom);
        var span=maximum-minimum; var lastX=left; var lastY=bottom; var drawn=0;
        for(var j=0;j<history.count;j++) {
            var x=history.count<=1 ? right : left+((j*(right-left))/(history.count-1)).toNumber();
            var point=history.value(j,cps);
            var y=span<=0 ? (top+bottom)/2 : bottom-(((point-minimum)*(bottom-top)/span).toNumber());
            if(drawn>0) { dc.drawLine(lastX,lastY,x,y); }
            else { dc.fillCircle(x,y,1); }
            lastX=x; lastY=y; drawn++;
        }
        fit(dc,width/2,height-dc.getFontHeight(G.FONT_XTINY)-1,"LAST 1h",
            width-20,G.FONT_XTINY,G.TEXT_JUSTIFY_CENTER);
    }
}
