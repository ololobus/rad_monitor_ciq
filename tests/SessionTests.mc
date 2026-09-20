using Toybox.Test;
using Toybox.Lang;
using Toybox.Time;
using Toybox.Application;
using Toybox.System;

// Fake GATT boundary; production initialization, framing and parsing run unchanged.
class SessionTransport {
    var owner; var sent as Lang.ByteArray=[]b; var state="INITIALIZING"; var error=null; var starts=0;
    function initialize(c) { owner=c; }
    function send(b) { sent=b; }
    function ready() { state="READY"; owner.onTransportState(state); }
    function stop() { state="DISCONNECTED"; }
    function start() { starts++; state="SCANNING"; }
    function fail(message) { state="ERROR"; error=message; owner.onTransportError(message); }
    function respond(payload, responseFirst) {
        var body=sent.slice(4,8); body.addAll(payload);
        var wire=RadiacodeProtocol.word(body.size()).addAll(body);
        if (!responseFirst) { owner.onWriteComplete(); }
        owner.onBytes(wire.slice(0,2)); owner.onBytes(wire.slice(2,wire.size()));
        if (responseFirst) { owner.onWriteComplete(); }
    }
}
(:test)
function initializeAndPoll(logger) {
    var c=new RadiacodeController();
    var link=new SessionTransport(c); c.transport=link;
    c.onSubscribed();
    Test.assert(RadiacodeProtocol.u16(link.sent,4)==7);
    link.respond([]b,true); // Response may arrive before the write completion event.
    Test.assert(RadiacodeProtocol.u16(link.sent,4)==0x0a04);
    Test.assert(link.sent.size()==16);
    link.respond([]b,false);
    Test.assert(RadiacodeProtocol.u16(link.sent,4)==0x0825);
    Test.assert(RadiacodeProtocol.u32(link.sent,8)==0x0504);
    link.respond([1,0,0,0]b,false);
    Test.assert(RadiacodeProtocol.u16(link.sent,4)==10);
    link.respond(Fixtures.firmware().slice(4,null),false);
    Test.assert(link.state.equals("READY"));
    Test.assert(c.firmware.equals("4.8"));
    c._running=true; c.tick();
    Test.assert(RadiacodeProtocol.u16(link.sent,4)==0x0826);
    Test.assert(RadiacodeProtocol.u32(link.sent,8)==0x0100);
    var previousStatus=Application.Storage.getValue(MeasurementStore.STATUS_KEY);
    Test.assert(link.sent[7]==132);
    // Avoid overwriting the simulator user's cached sample in this test.
    var previous=Application.Storage.getValue(MeasurementStore.KEY);
    var previousHistory=Application.Storage.getValue("history-v1");
    c._baseTime=Time.now().value()+126;
    link.respond(Fixtures.reply().slice(4,null),true);
    Test.assert(link.error==null);
    Test.assert(c.sample["cps"]==5.5);
    Test.assert(c.sample["timestamp"] instanceof Lang.Number);
    Test.assert(MeasurementStore.load()!=null);
    Test.assert(MeasurementStore.load()["cps"]==5.5);
    Application.Storage.setValue(MeasurementStore.KEY,previous);
    Application.Storage.setValue("history-v1",previousHistory);
    Application.Storage.setValue(MeasurementStore.STATUS_KEY,previousStatus);
    return true;
}
(:test)
function timeoutRetryAndStop(logger) {
    var c=new RadiacodeController(); var link=new SessionTransport(c); c.transport=link;
    c._running=true; c.onSubscribed(); c._deadline=0; c.tick();
    Test.assert(link.state.equals("ERROR"));
    Test.assert(!c._pending);
    c.retry(); c.tick(); Test.assert(link.starts==1);
    // A stop cancels future retry attempts.
    c.sample=null; c.stop(); c._retryAt=0; link.state="ERROR"; c.tick();
    Test.assert(link.starts==1);
    return true;
}
(:test)
function badEchoDoesNotAdvanceSession(logger) {
    var c=new RadiacodeController(); var link=new SessionTransport(c); c.transport=link;
    c.onSubscribed();
    link.sent[7]=129;
    link.respond([]b,false);
    Test.assert(link.state.equals("ERROR"));
    Test.assert(c._step==0 && !c._pending);
    return true;
}

(:test)
function recordGapDoesNotReconnect(logger) {
    var c=new RadiacodeController(); var link=new SessionTransport(c); c.transport=link;
    c._running=true; c._baseTime=Time.now().value()+126; link.state="READY";
    var previous=Application.Storage.getValue(MeasurementStore.KEY);
    var previousHistory=Application.Storage.getValue("history-v1");
    var previousStatus=Application.Storage.getValue(MeasurementStore.STATUS_KEY);
    c.tick();
    var b=Fixtures.reply(); b[34]=7;
    link.respond(b.slice(4,null),false);
    Test.assert(link.error==null && link.state.equals("READY"));
    Test.assert(c.recordGaps==1 && !c._pending);
    Test.assert(c.sample["cps"]==5.5);
    c._pollAt=0; c.tick();
    Test.assert(link.sent[7]==129); // Continue command counter, do not reinitialize.
    link.respond(Fixtures.reply().slice(4,null),true);
    Test.assert(link.error==null && link.starts==0 && c.sample["cps"]==5.5);
    Application.Storage.setValue(MeasurementStore.KEY,previous);
    Application.Storage.setValue("history-v1",previousHistory);
    Application.Storage.setValue(MeasurementStore.STATUS_KEY,previousStatus);
    return true;
}

(:test)
function unknownBacklogRecordDoesNotReconnect(logger) {
    var c=new RadiacodeController(); var link=new SessionTransport(c); c.transport=link;
    c._running=true; c._baseTime=Time.now().value()+126; link.state="READY";
    var previous=Application.Storage.getValue(MeasurementStore.KEY);
    var previousHistory=Application.Storage.getValue("history-v1");
    var previousStatus=Application.Storage.getValue(MeasurementStore.STATUS_KEY);
    c.tick();
    var b=Fixtures.reply(); b[35]=171; b[36]=170;
    link.respond(b.slice(4,null),false);
    Test.assert(link.error==null && link.state.equals("READY"));
    Test.assert(c.recordGaps==1 && c.sample["cps"]>4.19 && c.sample["cps"]<4.21);
    Test.assert(c.detail.equals("Skipped record 171/170"));
    c._pollAt=0; c.tick();
    link.respond(Fixtures.reply().slice(4,null),true);
    Test.assert(link.error==null && link.starts==0 && c.sample["cps"]==5.5);
    Application.Storage.setValue(MeasurementStore.KEY,previous);
    Application.Storage.setValue("history-v1",previousHistory);
    Application.Storage.setValue(MeasurementStore.STATUS_KEY,previousStatus);
    return true;
}
