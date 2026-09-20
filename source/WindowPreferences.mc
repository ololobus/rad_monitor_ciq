using Toybox.Application;
using Toybox.System;

module WindowPreferences {
    const KEY="window-battery-v1";
    var _loaded=false; var _battery=false;
    function battery() {
        if(!_loaded) {
            try { _battery=Application.Storage.getValue(KEY)==true; }
            catch(e) { System.println("RC settings: "+e.getErrorMessage()); }
            _loaded=true;
        }
        return _battery;
    }
    function setBattery(value) {
        // Update memory only if persistence succeeds.
        Application.Storage.setValue(KEY,value); _battery=value; _loaded=true;
    }
}
