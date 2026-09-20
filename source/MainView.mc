using Toybox.Graphics as G;
using Toybox.WatchUi;
using Toybox.Time;

class MainView extends WatchUi.View {
    var _c as RadiacodeController; var _started=false; var page=0;
    function initialize(c) { View.initialize(); _c=c; }
    function onShow() { if(!_started) { _started=true; _c.start(); } }
    function cycle(delta) { page=(page+delta+4)%4; WatchUi.requestUpdate(); }
    function onUpdate(dc) {
        ScreenLayout.clear(dc); ScreenLayout.deviceWindow(dc,_c.deviceStatus);
        if(page==3) { plot(dc); return; }
        if(page==2) { accumulated(dc); return; }
        ScreenLayout.title(dc,_c.transport.state);
        var s=_c.sample;
        if(s!=null) {
            var value=page==0 ? ScreenLayout.rate(s["dose"]) : ScreenLayout.count(s["cps"]);
            ScreenLayout.fit(dc,65,50,value,112,G.FONT_LARGE);
            ScreenLayout.fit(dc,65,82,page==0 ? "µSv/h" : "CPS",100,G.FONT_XTINY);
            var errorKey=page==0 ? "doseError" : "cpsError";
            var uncertainty=s.hasKey(errorKey) ? "± "+s[errorKey].format("%.1f")+"%" : "Uncertainty --";
            ScreenLayout.fit(dc,65,108,uncertainty,116,G.FONT_XTINY);
            var age=MeasurementStore.elapsed(s);
            var live=_c.transport.state.equals("READY") && age>=0 && age<=10;
            ScreenLayout.fit(dc,88,134,(live ? "Live " : "Stored ")+MeasurementStore.age(s),138,G.FONT_XTINY);
        } else {
            ScreenLayout.fit(dc,65,50,"--.---",110,G.FONT_LARGE);
            ScreenLayout.fit(dc,88,113,"Waiting for data",138,G.FONT_XTINY);
        }
    }
    function accumulated(dc) {
        ScreenLayout.title(dc,"DOSE");
        var s=_c.deviceStatus;
        ScreenLayout.fit(dc,65,50,s==null ? "--.---" : ScreenLayout.rate(s["accumulated"]),112,G.FONT_LARGE);
        ScreenLayout.fit(dc,65,82,"µSv",100,G.FONT_XTINY);
        var duration="Duration --";
        if(s!=null && s.hasKey("duration") && s["duration"]>=0) {
            var seconds=s["duration"];
            duration=(seconds/3600).toNumber().format("%d")+"h "+((seconds%3600)/60).toNumber().format("%02d")+"m "+(seconds%60).toNumber().format("%02d")+"s";
        }
        ScreenLayout.fit(dc,88,108,duration,140,G.FONT_XTINY);
        ScreenLayout.fit(dc,88,134,"App active time",150,G.FONT_XTINY);
    }
    function plot(dc) {
        var data=_c.history.points;
        var first=data.size()>360 ? data.size()-360 : 0;
        var minimum=0.0; var maximum=0.0;
        for(var i=0;i<data.size();i++) {
            if(i<first) { continue; }
            if(i==first) { minimum=data[i][1]; maximum=data[i][1]; }
            else {
                if(data[i][1]<minimum) { minimum=data[i][1]; }
                if(data[i][1]>maximum) { maximum=data[i][1]; }
            }
        }
        var current=_c.sample==null ? (data.size()==0 ? null : data[data.size()-1][1]) : _c.sample["dose"];
        ScreenLayout.fit(dc,59,10,current==null ? "--.---" : ScreenLayout.rate(current),86,G.FONT_XTINY);
        ScreenLayout.fit(dc,59,34,"µSv/h",86,G.FONT_XTINY);
        if(data.size()==0) {
            ScreenLayout.fit(dc,88,76,"No history yet",138,G.FONT_XTINY);
            ScreenLayout.fit(dc,88,145,"LAST 1h",110,G.FONT_XTINY); return;
        }
        ScreenLayout.fit(dc,22,66,ScreenLayout.rate(maximum),42,G.FONT_XTINY);
        ScreenLayout.fit(dc,22,112,ScreenLayout.rate(minimum),42,G.FONT_XTINY);
        // The circular hardware window ends at y=62. Keep the complete plot,
        // including its top edge, below it so high values cannot enter the window.
        var left=47; var right=158; var top=68; var bottom=137;
        dc.drawLine(left,top,left,bottom); dc.drawLine(left,bottom,right,bottom);
        var span=maximum-minimum; var lastX=0; var lastY=0; var drawn=0;
        var count=data.size()-first;
        for(var j=first;j<data.size();j++) {
            var x=count<=1 ? right : left+(((j-first)*(right-left))/(count-1)).toNumber();
            var y=span<=0 ? (top+bottom)/2 : bottom-(((data[j][1]-minimum)*(bottom-top)/span).toNumber());
            if(y<top) { y=top; } else if(y>bottom) { y=bottom; }
            if(drawn>0) { dc.drawLine(lastX,lastY,x,y); }
            else { dc.fillCircle(x,y,1); }
            lastX=x; lastY=y; drawn++;
        }
        ScreenLayout.fit(dc,88,145,"LAST 1h",110,G.FONT_XTINY);
    }
}
class MainDelegate extends WatchUi.BehaviorDelegate {
    var _c; var _view;
    function initialize(c,view) { BehaviorDelegate.initialize(); _c=c; _view=view; }
    function onNextPage() { _view.cycle(1); return true; }
    function onPreviousPage() { _view.cycle(-1); return true; }
    function onSelect() { _c.retry(); return true; }
    function onMenu() {
        var menu=new AppMenuView(_c);
        WatchUi.pushView(menu,new AppMenuDelegate(menu),WatchUi.SLIDE_UP); return true;
    }
}
