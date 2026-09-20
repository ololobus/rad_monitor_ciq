using Toybox.Application;
using Toybox.Time;
using Toybox.Lang;
using Toybox.System;

(:glance)
module MeasurementStore {
    const KEY="measurement-v1";
    function load() as Lang.Dictionary or Null {
        try {
            var s=Application.Storage.getValue(KEY);
            if (s instanceof Lang.Dictionary && s.hasKey("dose") && s.hasKey("cps") && s.hasKey("timestamp") &&
                s["dose"] instanceof Lang.Float && s["cps"] instanceof Lang.Float && s["timestamp"] instanceof Lang.Number) { return s; }
        } catch(e) { System.println("RC cache read: " + e.getErrorMessage()); }
        return null;
    }
    function save(sample) {
        try { Application.Storage.setValue(KEY,sample); }
        catch(e) { System.println("RC cache write: " + e.getErrorMessage()); }
    }
    const STATUS_KEY="device-status-v2";
    const LEGACY_STATUS_KEY="device-status-v1";
    function validStatus(s) {
        return s instanceof Lang.Dictionary && s.hasKey("accumulated") && s.hasKey("timestamp") &&
            s["accumulated"] instanceof Lang.Float && s["timestamp"] instanceof Lang.Number &&
            s["accumulated"]>=0 && (!s.hasKey("battery") ||
            (s["battery"] instanceof Lang.Float && s["battery"]>=0 && s["battery"]<=100));
    }
    function loadStatus() as Lang.Dictionary or Null {
        try {
            var s=Application.Storage.getValue(STATUS_KEY);
            if(validStatus(s)) { return s; }
            // v2 originally invalidated the working v1 cache. Preserve the last
            // detector battery while the live status stream catches up.
            s=Application.Storage.getValue(LEGACY_STATUS_KEY);
            if(validStatus(s)) { Application.Storage.setValue(STATUS_KEY,s); return s; }
        } catch(e) { System.println("RC status cache: "+e.getErrorMessage()); }
        return null;
    }
    function saveStatus(status) {
        try { Application.Storage.setValue(STATUS_KEY,status); }
        catch(e) { System.println("RC status save: "+e.getErrorMessage()); }
    }
    function elapsed(sample as Lang.Dictionary) {
        var seconds=Time.now().value()-sample["timestamp"];
        // Record decoding already accepts up to five seconds of device/watch
        // skew. Treat that same tolerance as current rather than a clock change.
        if(seconds<0 && seconds>=-5) { return 0; }
        return seconds;
    }
    function age(sample as Lang.Dictionary) {
        var seconds=elapsed(sample);
        if (seconds<0) { return "Clock changed"; }
        if (seconds<60) { return seconds.format("%d")+"s ago"; }
        if (seconds<3600) { return (seconds/60).format("%d")+"m ago"; }
        return (seconds/3600).format("%d")+"h ago";
    }
}
