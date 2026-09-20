using Toybox.Graphics as G;
using Toybox.Lang;
using Toybox.WatchUi;

// SDK simulator.json: main origin (101,158); 62px circle at (214,158).
// Its geometric center is (144,31); +1 x gives the physical display's observed
// optical alignment for both the launcher bitmap and battery ring.
module ScreenLayout {
    const WINDOW_X=145;
    const WINDOW_Y=31;
    var _logo=null;
    function clear(dc) { dc.setColor(G.COLOR_BLACK,G.COLOR_WHITE); dc.clear(); }
    function window(dc,text) {
        // Keep all content inside the circle; other UI never enters this region.
        if(text==null) {
            // Reuse the packaged 62 px launcher artwork verbatim. Besides keeping
            // every logo identical, this avoids rasterizing thousands of pixels
            // while the history plot is also being drawn.
            if(_logo==null) { _logo=WatchUi.loadResource(Rez.Drawables.LauncherIcon); }
            dc.drawBitmap(WINDOW_X-31,WINDOW_Y-31,_logo);
        }
        else { fit(dc,WINDOW_X,22,text,40,G.FONT_XTINY); }
    }
    function deviceWindow(dc,status as Lang.Dictionary or Null) {
        if(!WindowPreferences.battery()) { window(dc,null); return; }
        var value=status==null || !status.hasKey("battery") ? null : status["battery"];
        dc.setPenWidth(1); dc.drawCircle(WINDOW_X,WINDOW_Y,26);
        if(value!=null && value>0) {
            if(value>99) { value=99; }
            // Three explicit one-pixel arcs rasterize more cleanly than a
            // thick pen on the low-resolution MIP display.
            for(var r=22;r<=24;r++) {
                dc.drawArc(WINDOW_X,WINDOW_Y,r,G.ARC_CLOCKWISE,90,90-value*3.6);
            }
        }
        fit(dc,WINDOW_X,20,batteryLabel(value),46,G.FONT_XTINY);
    }
    function fit(dc,x,y,text,width,font) {
        var out=text;
        while(out.length()>0 && dc.getTextWidthInPixels(out,font)>width) {
            out=out.substring(0,out.length()-1);
        }
        dc.drawText(x,y,font,out,G.TEXT_JUSTIFY_CENTER);
    }
    function title(dc,text) { fit(dc,59,20,text,86,G.FONT_XTINY); }
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
    function batteryLabel(value) {
        if(value==null) { return "--%"; }
        if(value>99) { value=99; }
        return value.toNumber().format("%d")+"%";
    }
    function rows(dc,lines as Lang.Array,offset) {
        var y=70; var h=dc.getFontHeight(G.FONT_XTINY)+2;
        for(var i=offset;i<lines.size() && y+h<=162;i++) {
            fit(dc,88,y,lines[i],140,G.FONT_XTINY); y+=h;
        }
    }
    function wrap(dc,text) {
        var lines=[]; var start=0;
        while(start<text.length()) {
            var end=start+1;
            while(end<text.length() && dc.getTextWidthInPixels(text.substring(start,end+1),G.FONT_XTINY)<=138) { end++; }
            lines.add(text.substring(start,end)); start=end;
        }
        return lines;
    }
}
