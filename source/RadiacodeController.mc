using Toybox.Time;
using Toybox.Lang;
using Toybox.Time.Gregorian;
using Toybox.System;
using Toybox.Timer;
using Toybox.WatchUi;

class RadiacodeController {
    var transport; var sample as Lang.Dictionary or Null; var detail="Starting"; var firmware="";
    var deviceStatus as Lang.Dictionary or Null;
    var recordGaps=0; var history as HistoryStore;
    var _timer; var _running=false; var _frame; var _sequence=0; var _command; var _pending=false;
    var _reply; var _writeDone=false; var _step=0; var _deadline=0; var _pollAt=0;
    var _retryAt=0; var _retries=0; var _baseTime=0; var _savedAt=0; var _readTarget=0;
    var _doseLastTick=null; var _doseLastRate=null;
    function initialize() {
        transport=new RadiacodeBleTransport(self); _frame=new RadiacodeFrame();
        sample=MeasurementStore.load();
        var cached=MeasurementStore.loadStatus();
        var savedDose=cached!=null && cached.hasKey("sessionOnly") && cached["sessionOnly"]==true;
        var accumulated=savedDose ? cached["accumulated"] : 0.0;
        var duration=savedDose && cached.hasKey("duration") ? cached["duration"] : 0;
        deviceStatus={"accumulated"=>accumulated,"rawAccumulated"=>accumulated/10000.0,
            "duration"=>duration,"timestamp"=>Time.now().value(),"sessionOnly"=>true};
        if(cached!=null && cached.hasKey("battery")) { deviceStatus["battery"]=cached["battery"]; }
        history=new HistoryStore(true);
    }
    function acceptBattery(candidate as Lang.Dictionary,now) {
        if(deviceStatus==null) { return false; }
        deviceStatus["battery"]=candidate["battery"];
        deviceStatus["temperature"]=candidate["temperature"];
        MeasurementStore.saveStatus(deviceStatus);
        return true;
    }
    function accumulateAppDose(current as Lang.Dictionary,now,tick) {
        if(_doseLastTick!=null && tick>_doseLastTick) {
            var milliseconds=tick-_doseLastTick;
            // Each foreground run starts with no baseline. Also do not bridge
            // a BLE outage; only time covered by regular successful reads counts.
            if(milliseconds<=10000) {
                var seconds=milliseconds/1000.0;
                deviceStatus["accumulated"]+=((_doseLastRate+current["dose"])/2.0)*seconds/3600.0;
                deviceStatus["rawAccumulated"]=deviceStatus["accumulated"]/10000.0;
                deviceStatus["duration"]+=seconds.toNumber();
            }
        }
        _doseLastTick=tick;
        _doseLastRate=current["dose"];
        deviceStatus["timestamp"]=now;
        return true;
    }
    function resetAccumulatedDose() {
        deviceStatus["accumulated"]=0.0;
        deviceStatus["rawAccumulated"]=0.0;
        deviceStatus["duration"]=0;
        deviceStatus["timestamp"]=Time.now().value();
        deviceStatus["sessionOnly"]=true;
        _doseLastTick=null; _doseLastRate=null;
        MeasurementStore.saveStatus(deviceStatus);
        detail="Dose reset";
        WatchUi.requestUpdate();
    }
    function start() {
        _running=true; _timer=new Timer.Timer();
        _timer.start(method(:tick),2000,true); transport.start();
    }
    function stop() {
        _running=false;
        if (_timer!=null) { _timer.stop(); }
        transport.stop(); history.save();
        if (sample!=null) { MeasurementStore.save(sample); }
        if(deviceStatus!=null) { MeasurementStore.saveStatus(deviceStatus); }
    }
    function onTransportState(state) {
        detail=state; _deadline=System.getTimer()+(state.equals("SCANNING") ? 20000 : 12000);
        System.println("RC state=" + state); WatchUi.requestUpdate();
    }
    function onTransportError(message) {
        _pending=false; _reply=null; _readTarget=0; _frame.reset(); detail=message; history.pause();
        var delay=[5000,10000,20000,30000][_retries<4 ? _retries : 3];
        _retries++; _retryAt=System.getTimer()+delay;
        System.println("RC error=" + message + " retry(ms)=" + delay);
    }
    function retry() {
        if (!_running || !transport.state.equals("ERROR")) { return; }
        _retryAt=0;
    }
    function tick() as Void {
        if (!_running) { return; }
        var now=System.getTimer();
        if (transport.state.equals("ERROR")) {
            if (now>=_retryAt) { transport.start(); }
        } else if (_pending && now>=_deadline) {
            transport.fail("Reply timeout " + _command.format("%04x"));
        } else if (transport.state.equals("READY")) {
            if (!_pending && now>=_pollAt) {
                _readTarget=RadiacodeConstants.DATA_BUF;
                request(RadiacodeConstants.RD_VIRT_STRING,RadiacodeProtocol.word(_readTarget));
            }
        } else if (now>=_deadline) { transport.fail(transport.state+" timeout"); }
        WatchUi.requestUpdate();
    }
    function onSubscribed() { _step=0; _sequence=0; initializeStep(); }
    function initializeStep() {
        if (_step==0) { request(RadiacodeConstants.SET_EXCHANGE,[1,255,18,255]b); }
        else if (_step==1) {
            var t=Gregorian.info(Time.now(),Time.FORMAT_SHORT);
            request(RadiacodeConstants.SET_TIME,[t.day,t.month as Lang.Number,t.year-2000,0,t.sec,t.min,t.hour,0]b);
        } else if (_step==2) {
            request(RadiacodeConstants.WR_VIRT_SFR,RadiacodeProtocol.word(RadiacodeConstants.DEVICE_TIME).addAll([0,0,0,0]b));
        } else if (_step==3) { request(RadiacodeConstants.GET_VERSION,[]b); }
        else { transport.ready(); _pollAt=0; }
    }
    function request(command,args) {
        try {
            _command=command; _pending=true; _reply=null; _writeDone=false; _frame.reset();
            _deadline=System.getTimer()+10000;
            System.println("RC tx=" + command.format("%04x") + " seq=" + _sequence);
            transport.send(RadiacodeProtocol.request(command,_sequence,args));
        } catch(e) { transport.fail("Request: " + e.getErrorMessage()); }
    }
    function onWriteComplete() { _writeDone=true; complete(); }
    function onBytes(bytes) {
        if (!_pending) { transport.fail("Unexpected notify"); return; }
        try { _reply=_frame.feed(bytes); complete(); }
        catch(e) { transport.fail("Protocol: " + e.getErrorMessage()); }
    }
    function complete() {
        if (!_pending || !_writeDone || _reply==null) { return; }
        try {
            RadiacodeProtocol.checkHeader(_reply,_command,_sequence);
            _sequence=(_sequence+1)%32;
            var reply=_reply; _reply=null; _pending=false; _frame.reset();
            if (_command==RadiacodeConstants.WR_VIRT_SFR) {
                RadiacodeProtocol.require(reply.size()==8 && RadiacodeProtocol.u32(reply,4)==1,"Device time status");
                _baseTime=Time.now().value()+128;
            }
            if (_command==RadiacodeConstants.GET_VERSION) {
                firmware=RadiacodeProtocol.firmware(reply); System.println("RC firmware="+firmware);
            }
            if (_command==RadiacodeConstants.RD_VIRT_STRING && _readTarget==RadiacodeConstants.DATA_BUF) {
                var diagnostics={};
                var skippedRecord=null;
                var fresh=RadiacodeProtocol.decodeDataBuffer(reply,_baseTime,diagnostics);
                if (diagnostics.hasKey("expected")) {
                    recordGaps++;
                    detail="Record gap " + diagnostics["expected"] + ">" + diagnostics["actual"];
                    System.println("RC record gap: expected="+diagnostics["expected"]+
                        " actual="+diagnostics["actual"]+" offset="+diagnostics["offset"]+
                        " remaining="+diagnostics["remaining"]+" eid="+diagnostics["eid"]+
                        " gid="+diagnostics["gid"]+" total="+recordGaps);
                }
                if(diagnostics.hasKey("unknownEid")) {
                    recordGaps++;
                    skippedRecord="Skipped record "+diagnostics["unknownEid"]+"/"+diagnostics["unknownGid"];
                    System.println("RC skipped unknown record: seq="+diagnostics["unknownSeq"]+
                        " eid="+diagnostics["unknownEid"]+" gid="+diagnostics["unknownGid"]+
                        " offset="+diagnostics["unknownOffset"]+
                        " remaining="+diagnostics["unknownRemaining"]+" total="+recordGaps);
                }
                var statusChanged=diagnostics.hasKey("rare");
                if(statusChanged) {
                    var candidate=diagnostics["rare"] as Lang.Dictionary;
                    statusChanged=acceptBattery(candidate,Time.now().value());
                }
                if(statusChanged) {
                    System.println("RC battery="+deviceStatus["battery"]);
                }
                if (fresh!=null) {
                    var receivedAt=Time.now().value();
                    if(fresh["timestamp"]>receivedAt+5) {
                        System.println("RC sample clock ahead="+(fresh["timestamp"]-receivedAt)+"s; using receipt time");
                        fresh["timestamp"]=receivedAt;
                    }
                    sample=fresh; _retries=0;
                    accumulateAppDose(sample,receivedAt,System.getTimer());
                    history.add(sample["timestamp"],sample["dose"],System.getTimer());
                    System.println("RC sample uSv/h="+sample["dose"]+" cps="+sample["cps"]+" raw="+sample["rawDose"]+" flags="+sample["flags"]+" rt="+sample["rtFlags"]);
                    if (System.getTimer()-_savedAt>=15000 || _savedAt==0) {
                        MeasurementStore.save(sample); history.save();
                        if(deviceStatus!=null) { MeasurementStore.saveStatus(deviceStatus); }
                        _savedAt=System.getTimer();
                        System.println("RC freeMemory="+System.getSystemStats().freeMemory);
                    }
                }
                // Keep this anomaly visible in Diagnostics after all valid
                // battery/sample prefix data has been accepted and persisted.
                if(skippedRecord!=null) { detail=skippedRecord; }
                _readTarget=0;
                _pollAt=System.getTimer()+2000;
            } else { _step++; initializeStep(); }
            WatchUi.requestUpdate();
        } catch(e) { transport.fail("Protocol: " + e.getErrorMessage()); }
    }
}
