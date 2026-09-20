using Toybox.Test;
using Toybox.Application;
using Toybox.Lang;

(:test)
function historyAggregationAndCapacity(logger) {
    var h=new HistoryStore(false);
    h.add(100,0.1,0); h.add(103,0.3,3000);
    Test.assert(h.points.size()==1);
    Test.assert(h.points[0][1]>0.199 && h.points[0][1]<0.201);
    // Preserve remainder: 3-second polls do not stretch 10-second bins to 12s.
    for(var t=6000;t<3600000;t+=3000) { h.add(100+t/1000,0.2,t); }
    Test.assert(h.points.size()==360);
    h.add(3700,0.4,3600000);
    Test.assert(h.points.size()==360 && h.points[0][0]>103);
    return true;
}
(:test)
function historySurvivesRestartAndMarksPause(logger) {
    var old=Application.Storage.getValue("history-v1");
    var h=new HistoryStore(false); h.add(100,0.1,0); h.add(110,0.2,10000); h.save();
    var loaded=new HistoryStore(true);
    Test.assert(loaded.points.size()==2 && loaded.points[1][0]==110);
    // Days closed consume no slots; a new segment marks the recording pause.
    loaded.add(864100,0.3,0);
    Test.assert(loaded.points.size()==3 && loaded.points[2][2]==1);
    Test.assert(loaded.points[1][1]>0.199 && loaded.points[1][1]<0.201);
    loaded.add(864110,0.4,10000);
    Test.assert(loaded.points[3][2]==0);
    loaded.pause(); loaded.add(864111,0.5,11000);
    Test.assert(loaded.points[4][2]==1);
    Application.Storage.setValue("history-v1",old);
    return true;
}
(:test)
function corruptHistoryIgnored(logger) {
    var old=Application.Storage.getValue("history-v1");
    Application.Storage.setValue("history-v1",[1,2,3]b);
    Test.assert(new HistoryStore(true).points.size()==0);
    Application.Storage.setValue("history-v1",old);
    return true;
}
(:test)
function screenNavigationAndMenu(logger) {
    var c=new RadiacodeController();
    var view=new MainView(c); var delegate=new MainDelegate(c,view);
    Test.assert(view.page==0);
    delegate.onNextPage(); Test.assert(view.page==1);
    delegate.onNextPage(); Test.assert(view.page==2);
    delegate.onNextPage(); Test.assert(view.page==3);
    delegate.onNextPage(); Test.assert(view.page==0);
    delegate.onPreviousPage(); Test.assert(view.page==3);
    var menu=new AppMenuView(c);
    Test.assert(menu.getItem(0).getLabel().equals("Settings"));
    Test.assert(menu.getItem(1).getLabel().equals("Reset dose"));
    Test.assert(menu.getItem(2).getLabel().equals("Connected devices"));
    return true;
}

(:test)
function renderAllViewsWithNativeGraphics(logger) {
    var reference=Toybox.Graphics.createBufferedBitmap({:width=>176,:height=>176});
    var bitmap=reference.get(); var dc=bitmap.getDc();
    // Bounds prevent later opaque text cells erasing numbers/decimals.
    Test.assert(50+dc.getFontHeight(Toybox.Graphics.FONT_LARGE)<=82);
    Test.assert(82+dc.getFontHeight(Toybox.Graphics.FONT_XTINY)<=108);
    Test.assert(108+dc.getFontHeight(Toybox.Graphics.FONT_XTINY)<=134);
    Test.assert(134+dc.getFontHeight(Toybox.Graphics.FONT_XTINY)<=164);
    Test.assert(2*dc.getFontHeight(Toybox.Graphics.FONT_XTINY)<=61);
    var c=new RadiacodeController();
    c.sample={"dose"=>0.064,"cps"=>5.1,"timestamp"=>Toybox.Time.now().value()};
    c.history=new HistoryStore(false); c.history.add(100,0.064,0); c.history.add(110,0.08,10000);
    var main=new MainView(c); main.onUpdate(dc);
    for(var n=0;n<3;n++) { main.cycle(1); main.onUpdate(dc); }
    // The logo and densest plot must coexist within the device memory budget.
    var oldWindow=Toybox.Application.Storage.getValue(WindowPreferences.KEY);
    WindowPreferences.setBattery(false); WindowPreferences._loaded=false;
    main.page=3; main.onUpdate(dc);
    Toybox.Application.Storage.setValue(WindowPreferences.KEY,oldWindow); WindowPreferences._loaded=false;
    var menu=new AppMenuView(c); Test.assert(menu instanceof Toybox.WatchUi.Menu2);
    for(var section=0;section<3;section++) {
        var details=new DetailView(c,section); details.onUpdate(dc);
        Test.assert(details._count>=1 && details.offset==0);
        details.move(1); details.onUpdate(dc);
        Test.assert(details.offset==(details._count>1 ? 1 : 0));
    }
    var glance=new RadMonitorGlance(); glance.onUpdate(dc);
    return true;
}
