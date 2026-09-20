using Toybox.Test;
using Toybox.Lang;
using Toybox.Application;
using Toybox.Time;
using Toybox.System;

(:test)
function rareDataAndUncertainty(logger) {
    var diagnostics={};
    Test.assert(RadiacodeProtocol.decodeDataBuffer(StatusFixtures.reply(),1000,diagnostics)==null);
    var status=diagnostics["rare"] as Lang.Dictionary;
    Test.assert(status["duration"]==3661 && status["timestamp"]==872);
    Test.assert(status["battery"]>87.64 && status["battery"]<87.66);
    Test.assert(status["temperature"]>23.44 && status["temperature"]<23.46);
    Test.assert(status["accumulated"]>2.499 && status["accumulated"]<2.501);
    var mixed=StatusFixtures.reply().addAll(Fixtures.reply().slice(12,null));
    mixed.encodeNumber(mixed.size()-12,Lang.NUMBER_FORMAT_UINT32,{:offset=>8,:endianness=>Lang.ENDIAN_LITTLE});
    diagnostics={};
    var sample=RadiacodeProtocol.decodeDataBuffer(mixed,1000,diagnostics);
    Test.assert(sample["cpsError"]==1.5 && sample["doseError"]==2.0);
    Test.assert(diagnostics.hasKey("rare"));
    Test.assert(diagnostics["doseUntil"]==874);
    Test.assert((diagnostics["doseDelta"] as Lang.Float)>0.0);
    return true;
}

(:test)
function appDoseUsesRuntimeAndCanReset(logger) {
    var old=Application.Storage.getValue(MeasurementStore.STATUS_KEY);
    var c=new RadiacodeController();
    c.deviceStatus={"accumulated"=>0.0,"rawAccumulated"=>0.0,
        "duration"=>0,"timestamp"=>1000,"sessionOnly"=>true};
    // Detector timestamps are irrelevant to app-active integration.
    Test.assert(c.accumulateAppDose({"timestamp"=>9000,"dose"=>0.09},1000,1000));
    Test.assert(c.accumulateAppDose({"timestamp"=>500,"dose"=>0.18},1002,3000));
    Test.assert(c.deviceStatus["duration"]==2);
    Test.assert(c.deviceStatus["accumulated"]>0.000074 && c.deviceStatus["accumulated"]<0.000076);
    // A long connection gap establishes a new baseline without bridging it.
    Test.assert(c.accumulateAppDose({"timestamp"=>501,"dose"=>20.0},1020,20000));
    Test.assert(c.deviceStatus["duration"]==2);
    // A new foreground controller resumes the saved app-active total, but its
    // first read is only a baseline and cannot bridge time spent closed.
    MeasurementStore.saveStatus(c.deviceStatus);
    var reopened=new RadiacodeController();
    Test.assert(reopened.deviceStatus["duration"]==2);
    Test.assert(reopened.deviceStatus["accumulated"]>0.000074);
    reopened.accumulateAppDose({"timestamp"=>9999,"dose"=>0.18},2000,40000);
    Test.assert(reopened.deviceStatus["duration"]==2);
    reopened.resetAccumulatedDose();
    Test.assert(reopened.deviceStatus["duration"]==0 && reopened.deviceStatus["accumulated"]==0.0);
    Application.Storage.setValue(MeasurementStore.STATUS_KEY,old);
    return true;
}
(:test)
function statusOnlyResponsePersists(logger) {
    var old=Application.Storage.getValue(MeasurementStore.STATUS_KEY);
    var c=new RadiacodeController(); var link=new SessionTransport(c); c.transport=link;
    c.sample=null; c._baseTime=Time.now().value()+128;
    c._running=true; link.state="READY"; c.tick();
    link.respond(StatusFixtures.reply().slice(4,null),true);
    Test.assert(link.error==null && c.sample==null && !c._pending);
    Test.assert(c.deviceStatus["duration"]==0);
    Test.assert(MeasurementStore.loadStatus()["battery"]>87.64);
    // The first successful foreground sample establishes the dose baseline.
    c._pollAt=0; c.tick();
    var previous=Application.Storage.getValue(MeasurementStore.KEY);
    var history=Application.Storage.getValue("history-v1");
    link.respond(Fixtures.reply().slice(4,null),false);
    Test.assert(c.deviceStatus["duration"]==0 && c.sample!=null);
    Application.Storage.setValue(MeasurementStore.KEY,previous);
    Application.Storage.setValue("history-v1",history);
    Application.Storage.setValue(MeasurementStore.STATUS_KEY,old);
    return true;
}
(:test)
function rareGapAndTruncation(logger) {
    var b=StatusFixtures.reply().addAll(Fixtures.reply().slice(12,null));
    b.encodeNumber(b.size()-12,Lang.NUMBER_FORMAT_UINT32,{:offset=>8,:endianness=>Lang.ENDIAN_LITTLE});
    b[33]=99; // Gap after complete RareData; valid following RT still parses.
    var diagnostics={};
    Test.assert(RadiacodeProtocol.decodeDataBuffer(b,1000,diagnostics)!=null);
    Test.assert(diagnostics.hasKey("rare") && diagnostics.hasKey("expected"));
    // A filtered reply can put RareData after a sequence gap. The complete
    // record must still decode after the earlier real-time record.
    b=Fixtures.reply().slice(0,34).addAll(StatusFixtures.reply().slice(12,null));
    b.encodeNumber(b.size()-12,Lang.NUMBER_FORMAT_UINT32,{:offset=>8,:endianness=>Lang.ENDIAN_LITTLE});
    diagnostics={};
    Test.assert(RadiacodeProtocol.decodeDataBuffer(b,1000,diagnostics)!=null);
    var status=diagnostics["rare"] as Lang.Dictionary;
    Test.assert(status["duration"]==3661);
    Test.assert(status["battery"]>87.64 && status["battery"]<87.66);
    Test.assert(status["accumulated"]>2.499 && status["accumulated"]<2.501);
    Test.assert(diagnostics.hasKey("expected"));
    b=StatusFixtures.reply().slice(0,32);
    b.encodeNumber(20,Lang.NUMBER_FORMAT_UINT32,{:offset=>8,:endianness=>Lang.ENDIAN_LITTLE});
    try { RadiacodeProtocol.decodeDataBuffer(b,1000,{}); } catch(e) { return true; }
    return false;
}
(:test)
function batterySettingsAndRendering(logger) {
    var old=Application.Storage.getValue(WindowPreferences.KEY);
    var oldStatus=Application.Storage.getValue(MeasurementStore.STATUS_KEY);
    var oldLegacy=Application.Storage.getValue(MeasurementStore.LEGACY_STATUS_KEY);
    WindowPreferences.setBattery(true); WindowPreferences._loaded=false;
    Test.assert(WindowPreferences.battery());
    var reference=Toybox.Graphics.createBufferedBitmap({:width=>176,:height=>176});
    var dc=reference.get().getDc();
    var diagnostics={}; RadiacodeProtocol.decodeDataBuffer(StatusFixtures.reply(),1000,diagnostics);
    var status=diagnostics["rare"] as Lang.Dictionary;
    // Existing sideload installations used v1; upgrading must not hide it.
    Application.Storage.setValue(MeasurementStore.STATUS_KEY,null);
    Application.Storage.setValue(MeasurementStore.LEGACY_STATUS_KEY,status);
    Test.assert(MeasurementStore.loadStatus()["battery"]>87.64);
    ScreenLayout.clear(dc); ScreenLayout.deviceWindow(dc,null);
    var levels=[0.0,1.0,50.0,99.0,100.0];
    for(var i=0;i<levels.size();i++) {
        status["battery"]=levels[i]; ScreenLayout.clear(dc); ScreenLayout.deviceWindow(dc,status);
    }
    Test.assert(ScreenLayout.batteryLabel(100.0).equals("99%"));
    Test.assert(ScreenLayout.batteryLabel(99.0).equals("99%"));
    Test.assert(ScreenLayout.batteryLabel(null).equals("--%"));
    var c=new RadiacodeController(); c.deviceStatus=status;
    var view=new MainView(c); view.page=2; view.onUpdate(dc);
    var settings=new SettingsView(); Test.assert(settings.getItem(0).getSubLabel().equals("Device battery"));
    WindowPreferences.setBattery(false); settings.refresh();
    Test.assert(settings.getItem(0).getSubLabel().equals("Logo"));
    MeasurementStore.saveStatus(status);
    var glanceRef=Toybox.Graphics.createBufferedBitmap({:width=>164,:height=>61});
    new RadMonitorGlance().onUpdate(glanceRef.get().getDc());
    Application.Storage.setValue(WindowPreferences.KEY,old); WindowPreferences._loaded=false;
    Application.Storage.setValue(MeasurementStore.STATUS_KEY,oldStatus);
    Application.Storage.setValue(MeasurementStore.LEGACY_STATUS_KEY,oldLegacy);
    return true;
}

(:test)
function batteryUpdatesDespiteDetectorClockSkew(logger) {
    var c=new RadiacodeController();
    c.deviceStatus={"accumulated"=>0.025,"rawAccumulated"=>0.0000025,
        "duration"=>100,"timestamp"=>6000,"sessionOnly"=>true};
    Test.assert(c.acceptBattery({"timestamp"=>1000,"battery"=>82.0,"temperature"=>20.0},6000));
    // Receipt order wins even when the detector clock jumps backward or ahead.
    Test.assert(c.acceptBattery({"timestamp"=>999,"battery"=>74.0,"temperature"=>20.0},6001));
    Test.assert(c.acceptBattery({"timestamp"=>9000,"battery"=>71.0,"temperature"=>20.0},6002));
    Test.assert(c.deviceStatus["battery"]==71.0);
    Test.assert(c.deviceStatus["accumulated"]==0.025 && c.deviceStatus["duration"]==100);
    return true;
}

(:test)
function futureSampleDoesNotReconnect(logger) {
    var old=Application.Storage.getValue(MeasurementStore.STATUS_KEY);
    var c=new RadiacodeController(); var link=new SessionTransport(c); c.transport=link;
    c.sample=null; c._baseTime=Time.now().value()+1000;
    c._running=true; link.state="READY"; c.tick();
    var mixed=StatusFixtures.reply().addAll(Fixtures.reply().slice(12,null));
    mixed.encodeNumber(mixed.size()-12,Lang.NUMBER_FORMAT_UINT32,{:offset=>8,:endianness=>Lang.ENDIAN_LITTLE});
    link.respond(mixed.slice(4,null),false);
    Test.assert(link.error==null && link.state.equals("READY"));
    Test.assert(c.sample!=null && MeasurementStore.elapsed(c.sample)==0);
    Test.assert(c.deviceStatus["battery"]>87.64);
    Application.Storage.setValue(MeasurementStore.STATUS_KEY,old);
    return true;
}

(:test)
function doseResetEventDecoded(logger) {
    var b=[38,8,0,128,1,0,0,0,11,0,0,0,1,0,7,156,255,255,255,4,0,0,0]b;
    var diagnostics={};
    Test.assert(RadiacodeProtocol.decodeDataBuffer(b,1000,diagnostics)==null);
    Test.assert(diagnostics.hasKey("doseReset") && diagnostics["doseReset"]==999);
    return true;
}

(:test)
function smallFutureTimestampIsCurrent(logger) {
    var now=Time.now().value();
    var tolerated={"timestamp"=>now+5};
    Test.assert(MeasurementStore.elapsed(tolerated)==0);
    Test.assert(MeasurementStore.age(tolerated).equals("0s ago"));
    var changed={"timestamp"=>now+60};
    Test.assert(MeasurementStore.elapsed(changed)<0);
    Test.assert(MeasurementStore.age(changed).equals("Clock changed"));
    return true;
}
