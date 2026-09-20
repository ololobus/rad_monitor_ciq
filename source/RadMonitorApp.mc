using Toybox.Application;

(:glance)
class RadMonitorApp extends Application.AppBase {
    var _controller;
    function initialize() { AppBase.initialize(); }
    function onStart(state) {}
    function getInitialView() {
        _controller=new RadiacodeController();
        var view=new MainView(_controller);
        return [view, new MainDelegate(_controller,view)];
    }
    function getGlanceView() { return [new RadMonitorGlance()]; }
    function onStop(state) {
        if (_controller!=null) { _controller.stop(); _controller=null; }
    }
}
