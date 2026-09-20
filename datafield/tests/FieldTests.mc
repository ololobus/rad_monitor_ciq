using Toybox.Test;
using Toybox.Time;

(:test)
function fieldHistoryTracksBothMetrics(logger) {
    var history=new FieldHistory();
    history.add(0.1,2.0,0); history.add(0.3,4.0,5000);
    Test.assert(history.count==1);
    Test.assert(history.value(0,false)>0.199 && history.value(0,false)<0.201);
    Test.assert(history.value(0,true)>2.99 && history.value(0,true)<3.01);
    history.add(0.5,6.0,10000);
    Test.assert(history.count==2);
    Test.assert(history.value(1,false)>0.499 && history.value(1,false)<0.501);
    Test.assert(history.value(1,true)>5.99 && history.value(1,true)<6.01);
    return true;
}

(:test)
function fieldHistoryIsBoundedRing(logger) {
    var history=new FieldHistory();
    for(var i=0;i<=history.CAPACITY;i++) {
        history.add(i.toFloat(),(i*2).toFloat(),i*10000);
    }
    Test.assert(history.count==history.CAPACITY);
    Test.assert(history.value(0,false)>0.99 && history.value(0,false)<1.01);
    Test.assert(history.value(history.count-1,true)>719.9);
    return true;
}

class FieldSessionTransport {
    var owner; var sent=[]b; var state="INITIALIZING"; var error=null;
    function initialize(controller) { owner=controller; }
    function send(bytes) { sent=bytes; }
    function ready() { state="READY"; owner.onTransportState(state); }
    function start() { state="SCANNING"; }
    function stop() { state="DISCONNECTED"; }
    function fail(message) { state="ERROR"; error=message; owner.onTransportError(message); }
    function respond(payload,responseFirst) {
        var body=sent.slice(4,8); body.addAll(payload);
        var wire=RadiacodeProtocol.word(body.size()).addAll(body);
        if(!responseFirst) { owner.onWriteComplete(); }
        owner.onBytes(wire);
        if(responseFirst) { owner.onWriteComplete(); }
    }
}

(:test)
function fieldControllerInitializesAndPollsWithoutTimer(logger) {
    var controller=new FieldController();
    var link=new FieldSessionTransport(controller); controller.transport=link;
    controller.onSubscribed();
    Test.assert(RadiacodeProtocol.u16(link.sent,4)==RadiacodeConstants.SET_EXCHANGE);
    link.respond([]b,true); link.respond([]b,false);
    link.respond([1,0,0,0]b,false);
    link.respond(Fixtures.firmware().slice(4,null),false);
    Test.assert(link.state.equals("READY"));
    controller._running=true; controller.tick();
    Test.assert(RadiacodeProtocol.u16(link.sent,4)==RadiacodeConstants.RD_VIRT_STRING);
    controller._baseTime=Time.now().value()+126;
    link.respond(Fixtures.reply().slice(4,null),true);
    Test.assert(link.error==null && controller.sampleSerial==1);
    Test.assert(controller.sample["cps"]==5.5 && controller.history.count==1);
    return true;
}
