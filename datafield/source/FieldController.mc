using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;

// Data fields have no Timer API. compute() calls tick once per second and this
// controller schedules the same two-second, single-request polling discipline
// as the watch app without loading its caches, menus, dose integrator or glance.
class FieldController {
    var transport; var sample as Lang.Dictionary or Null;
    var history=new FieldHistory(); var sampleSerial=0;
    var _running=false; var _frame=new RadiacodeFrame(); var _sequence=0;
    var _command=0; var _pending=false; var _reply; var _writeDone=false;
    var _step=0; var _deadline=0; var _pollAt=0; var _retryAt=0;
    var _retries=0; var _baseTime=0; var _readTarget=0;

    function initialize() { transport=new RadiacodeBleTransport(self); }
    function start() { _running=true; transport.start(); }
    function stop() { _running=false; transport.stop(); history.pause(); }
    function onTransportState(state) {
        _deadline=System.getTimer()+(state.equals("SCANNING") ? 20000 : 12000);
        WatchUi.requestUpdate();
    }
    function onTransportError(message) {
        _pending=false; _reply=null; _readTarget=0; _frame.reset(); history.pause();
        var delays=[5000,10000,20000,30000];
        _retryAt=System.getTimer()+delays[_retries<4 ? _retries : 3]; _retries++;
        WatchUi.requestUpdate();
    }
    function tick() {
        if(!_running) { return; }
        var now=System.getTimer();
        if(transport.state.equals("ERROR")) {
            if(now>=_retryAt) { transport.start(); }
        } else if(_pending && now>=_deadline) {
            transport.fail("Reply timeout");
        } else if(transport.state.equals("READY")) {
            if(!_pending && now>=_pollAt) {
                _readTarget=RadiacodeConstants.DATA_BUF;
                request(RadiacodeConstants.RD_VIRT_STRING,RadiacodeProtocol.word(_readTarget));
            }
        } else if(now>=_deadline) { transport.fail(transport.state+" timeout"); }
    }
    function onSubscribed() { _step=0; _sequence=0; initializeStep(); }
    function initializeStep() {
        if(_step==0) { request(RadiacodeConstants.SET_EXCHANGE,[1,255,18,255]b); }
        else if(_step==1) {
            var t=Gregorian.info(Time.now(),Time.FORMAT_SHORT);
            request(RadiacodeConstants.SET_TIME,[t.day,t.month as Lang.Number,t.year-2000,0,t.sec,t.min,t.hour,0]b);
        } else if(_step==2) {
            request(RadiacodeConstants.WR_VIRT_SFR,
                RadiacodeProtocol.word(RadiacodeConstants.DEVICE_TIME).addAll([0,0,0,0]b));
        } else if(_step==3) { request(RadiacodeConstants.GET_VERSION,[]b); }
        else { transport.ready(); _pollAt=0; }
    }
    function request(command,args) {
        try {
            _command=command; _pending=true; _reply=null; _writeDone=false; _frame.reset();
            _deadline=System.getTimer()+10000;
            transport.send(RadiacodeProtocol.request(command,_sequence,args));
        } catch(e) { transport.fail("Request"); }
    }
    function onWriteComplete() { _writeDone=true; complete(); }
    function onBytes(bytes) {
        if(!_pending) { transport.fail("Unexpected notify"); return; }
        try { _reply=_frame.feed(bytes); complete(); }
        catch(e) { transport.fail("Protocol"); }
    }
    function complete() {
        if(!_pending || !_writeDone || _reply==null) { return; }
        try {
            RadiacodeProtocol.checkHeader(_reply,_command,_sequence);
            _sequence=(_sequence+1)%32;
            var reply=_reply; _reply=null; _pending=false; _frame.reset();
            if(_command==RadiacodeConstants.WR_VIRT_SFR) {
                RadiacodeProtocol.require(reply.size()==8 && RadiacodeProtocol.u32(reply,4)==1,
                    "Device time status");
                _baseTime=Time.now().value()+128;
            }
            if(_command==RadiacodeConstants.GET_VERSION) { RadiacodeProtocol.firmware(reply); }
            if(_command==RadiacodeConstants.RD_VIRT_STRING &&
                _readTarget==RadiacodeConstants.DATA_BUF) {
                var fresh=RadiacodeProtocol.decodeDataBuffer(reply,_baseTime,null);
                if(fresh!=null) {
                    var receivedAt=Time.now().value();
                    if(fresh["timestamp"]>receivedAt+5) { fresh["timestamp"]=receivedAt; }
                    sample=fresh; _retries=0; sampleSerial++;
                    history.add(sample["dose"],sample["cps"],System.getTimer());
                }
                _readTarget=0; _pollAt=System.getTimer()+2000;
            } else { _step++; initializeStep(); }
            WatchUi.requestUpdate();
        } catch(e) { transport.fail("Protocol"); }
    }
}
