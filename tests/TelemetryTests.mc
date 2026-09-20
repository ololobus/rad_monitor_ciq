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
function bufferedDoseIncludesDisconnectedRecords(logger) {
    var c=new RadiacodeController();
    c.deviceStatus={"accumulated"=>0.025,"rawAccumulated"=>0.0000025,
        "duration"=>100,"timestamp"=>1000,"sourceTimestamp"=>1000,
        "doseIntegratedUntil"=>1000};
    Test.assert(c.advanceBufferedDose(0.035,2800,2801));
    Test.assert(c.deviceStatus["accumulated"]>0.0599 && c.deviceStatus["accumulated"]<0.0601);
    Test.assert(c.deviceStatus["duration"]==1900);
    Test.assert(!c.advanceBufferedDose(1.0,2800,2802));
    Test.assert(c.deviceStatus["accumulated"]<0.0601);
    return true;
}
(:test)
function statusOnlyResponsePersists(logger) {
    var old=Application.Storage.getValue(MeasurementStore.STATUS_KEY);
    var c=new RadiacodeController(); var link=new SessionTransport(c); c.transport=link;
    c.sample=null; c.deviceStatus=null; c._baseTime=Time.now().value()+128;
    c._running=true; c._statusPollAt=System.getTimer()+60000; link.state="READY"; c.tick();
    link.respond(StatusFixtures.reply().slice(4,null),true);
    Test.assert(link.error==null && c.sample==null && !c._pending);
    Test.assert(c.deviceStatus["duration"]==3661);
    Test.assert(MeasurementStore.loadStatus()["battery"]>87.64);
    // Real-time-only buffers must retain the last separate battery/dose status.
    c._pollAt=0; c.tick();
    var previous=Application.Storage.getValue(MeasurementStore.KEY);
    var history=Application.Storage.getValue("history-v1");
    link.respond(Fixtures.reply().slice(4,null),false);
    Test.assert(c.deviceStatus["duration"]==3661 && c.sample!=null);
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
    // A filtered reply can put the cumulative status after a sequence gap.
    // It must still supply battery and total dose after the earlier RT record.
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
function historicalStatusCannotReplaceCurrent(logger) {
    var c=new RadiacodeController(); c.deviceStatus=null;
    Test.assert(c.acceptStatus({"timestamp"=>1000,"battery"=>32.0,"accumulated"=>18.24,"duration"=>886410},1000+3814*3600));
    Test.assert(c.deviceStatus["timestamp"]==1000+3814*3600);
    // A newer cumulative snapshot wins even when its packet timestamp is old.
    Test.assert(c.acceptStatus({"timestamp"=>2000,"battery"=>83.0,"accumulated"=>28.2,"duration"=>1684800},2000+3814*3600));
    Test.assert(!c.acceptStatus({"timestamp"=>1999,"battery"=>20.0,"accumulated"=>10.0,"duration"=>500000},2000+3814*3600));
    Test.assert(!c.acceptStatus({"timestamp"=>2000+3814*3600+10,"battery"=>30.0,"accumulated"=>30.0,"duration"=>1700000},2000+3814*3600));
    Test.assert(c.deviceStatus["battery"]==83.0 && c.deviceStatus["accumulated"]==28.2);
    // Resetting accumulated dose is legitimate when the record itself is newer.
    Test.assert(c.acceptStatus({"timestamp"=>2001+3814*3600,"battery"=>83.0,"accumulated"=>0.0,"duration"=>0},2001+3814*3600));
    // A dose-reset event clears the cached total immediately and blocks older
    // buffered status from restoring the pre-reset value.
    c.resetDose(5000,6000);
    Test.assert(c.deviceStatus["accumulated"]==0.0 && c.deviceStatus["duration"]==0);
    Test.assert(!c.acceptStatus({"timestamp"=>4999,"battery"=>82.0,"accumulated"=>28.34,"duration"=>1350013},6000));
    Test.assert(c.acceptDirectDose(1234,6010));
    Test.assert(c.deviceStatus["accumulated"]>12.339 && c.deviceStatus["accumulated"]<12.341);
    // Buffered status arriving after the direct read may update battery and
    // duration, but must not restore its older accumulated dose.
    Test.assert(c.acceptStatus({"timestamp"=>5001,"battery"=>81.0,
        "accumulated"=>28.34,"rawAccumulated"=>0.002834,"duration"=>1350013},6011));
    Test.assert(c.deviceStatus["battery"]==81.0);
    Test.assert(c.deviceStatus["accumulated"]>12.339 && c.deviceStatus["accumulated"]<12.341);
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
