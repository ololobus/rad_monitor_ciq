using Toybox.WatchUi;
using Toybox.Graphics as G;
using Toybox.System;
using Toybox.Lang;

// Garmin owns selection, scrolling, text layout and the Solar subscreen.
class AppMenuView extends WatchUi.Menu2 {
    var controller;
    function initialize(c) {
        Menu2.initialize({:title=>"RadMonitor"}); controller=c;
        addItem(new WatchUi.MenuItem("Settings",null,3,{}));
        addItem(new WatchUi.MenuItem("Connected devices",null,0,{}));
        addItem(new WatchUi.MenuItem("Diagnostics",null,1,{}));
        addItem(new WatchUi.MenuItem("Info",null,2,{}));
    }
}
class AppMenuDelegate extends WatchUi.Menu2InputDelegate {
    var _view;
    function initialize(v) { Menu2InputDelegate.initialize(); _view=v; }
    function onSelect(item) {
        var section=item.getId();
        if(section==3) {
            var settings=new SettingsView();
            WatchUi.pushView(settings,new SettingsDelegate(settings),WatchUi.SLIDE_UP);
        } else {
            var page=new DetailView(_view.controller,section);
            WatchUi.pushView(page,new DetailDelegate(page),WatchUi.SLIDE_UP);
        }
    }
}
class DetailView extends WatchUi.View {
    const ROWS_PER_PAGE=3;
    var _c; var _section; var offset=0; var _count=0;
    function initialize(c,section) { View.initialize(); _c=c; _section=section; }
    function move(delta) {
        offset+=delta;
        if(offset<0) { offset=0; }
        if(offset>=_count) { offset=_count>0 ? _count-1 : 0; }
        WatchUi.requestUpdate();
    }
    function onUpdate(dc) {
        ScreenLayout.clear(dc);
        var titles=["DEVICES","DIAG","INFO"];
        ScreenLayout.title(dc,titles[_section]);
        var lines=[];
        if(_section==0) {
            var connected=_c.transport.state.equals("READY") || _c.transport.state.equals("INITIALIZING");
            lines.add(connected ? "1 connected" : "No ready device");
            if(!_c.transport.deviceName.equals("")) { lines.addAll(ScreenLayout.wrap(dc,_c.transport.deviceName)); }
            lines.add(_c.transport.state);
            lines.add("Firmware "+_c.firmware);
            lines.add("Direct BLE");
        } else if(_section==1) {
            lines.add(_c.transport.state); lines.add("FW "+_c.firmware);
            lines.add("RX "+_c.transport.notifications); lines.add("Record gaps "+_c.recordGaps);
            lines.add("Free "+System.getSystemStats().freeMemory);
            lines.addAll(ScreenLayout.wrap(dc,_c.detail));
        } else {
            lines.add("RadMonitor "+BuildInfo.VERSION);
            lines.addAll(ScreenLayout.wrap(dc,"Build "+BuildInfo.BUILT));
            lines.add("SDK "+BuildInfo.SDK); lines.add("Instinct 3 Solar");
            lines.add("History: 1h recorded"); lines.add("10s mean / µSv/h");
            lines.add("MIT license"); lines.add("cdump/radiacode");
        }
        _count=((lines.size()+ROWS_PER_PAGE-1)/ROWS_PER_PAGE).toNumber();
        if(_count<1) { _count=1; }
        if(offset>=_count) { offset=_count-1; }
        ScreenLayout.window(dc,(offset+1).format("%d")+"/"+_count.format("%d"));
        ScreenLayout.rows(dc,lines,offset*ROWS_PER_PAGE);
    }
}
class DetailDelegate extends WatchUi.BehaviorDelegate {
    var _view;
    function initialize(v) { BehaviorDelegate.initialize(); _view=v; }
    function onNextPage() { _view.move(1); return true; }
    function onPreviousPage() { _view.move(-1); return true; }
    function onBack() { WatchUi.popView(WatchUi.SLIDE_DOWN); return true; }
}

class SettingsView extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title=>"Settings"});
        addItem(new WatchUi.MenuItem("Window data",WindowPreferences.battery() ? "Device battery" : "Logo",0,{}));
    }
    function refresh() { getItem(0).setSubLabel(WindowPreferences.battery() ? "Device battery" : "Logo"); }
}
class SettingsDelegate extends WatchUi.Menu2InputDelegate {
    var _view;
    function initialize(v) { Menu2InputDelegate.initialize(); _view=v; }
    function onSelect(item) {
        var options=new WatchUi.Menu2({:title=>"Window data",:focus=>WindowPreferences.battery() ? 1 : 0});
        options.addItem(new WatchUi.MenuItem("Logo",null,0,{}));
        options.addItem(new WatchUi.MenuItem("Device battery",null,1,{}));
        WatchUi.pushView(options,new WindowDataDelegate(_view),WatchUi.SLIDE_UP);
    }
}
class WindowDataDelegate extends WatchUi.Menu2InputDelegate {
    var _settings;
    function initialize(v) { Menu2InputDelegate.initialize(); _settings=v; }
    function onSelect(item) {
        try {
            WindowPreferences.setBattery(item.getId()==1); _settings.refresh();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } catch(e) { item.setSubLabel("Save failed"); WatchUi.requestUpdate(); }
    }
}
