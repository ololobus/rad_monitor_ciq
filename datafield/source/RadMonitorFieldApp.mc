using Toybox.Application;
using Toybox.WatchUi;

class RadMonitorFieldApp extends Application.AppBase {
    var controller;
    function initialize() { AppBase.initialize(); }
    function onStart(state) {
        controller=new FieldController(); controller.start();
    }
    function getInitialView() { return [new RadMonitorFieldView(controller)]; }
    function onSettingsChanged() { WatchUi.requestUpdate(); }
    function onStop(state) {
        if(controller!=null) { controller.stop(); controller=null; }
    }
}
