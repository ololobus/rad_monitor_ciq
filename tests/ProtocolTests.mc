using Toybox.Test;
using Toybox.Lang;
using Toybox.System;

(:test)
function requestVector(logger) {
    var b=RadiacodeProtocol.request(7,0,[1,255,18,255]b);
    var expected=[8,0,0,0,7,0,0,128,1,255,18,255]b;
    Test.assert(b.size()==expected.size());
    for(var i=0;i<b.size();i++) { Test.assert(b[i]==expected[i]); }
    Test.assert(RadiacodeProtocol.request(7,32,[]b)[7]==128);
    return true;
}
(:test)
function fragmentedResponse(logger) {
    var body=Fixtures.reply(); var wire=RadiacodeProtocol.word(body.size()).addAll(body);
    // Every possible two-fragment boundary, including inside the length/header/floats.
    for(var cut=1;cut<wire.size();cut++) {
        var rx=new RadiacodeFrame();
        Test.assert(rx.feed(wire.slice(0,cut))==null);
        var result=rx.feed(wire.slice(cut,wire.size()));
        Test.assert(result.size()==body.size());
        for(var i=0;i<body.size();i++) { Test.assert(result[i]==body[i]); }
    }
    var single=new RadiacodeFrame(); var last=null;
    for(var j=0;j<wire.size();j++) { last=single.feed(wire.slice(j,j+1)); }
    Test.assert(last.size()==body.size());
    return true;
}
(:test)
function boundedFrames(logger) {
    var rejected=0;
    var lengths=[0,3,8193,0x7fffffff];
    for(var k=0;k<lengths.size();k++) {
        var n=lengths[k];
        try { new RadiacodeFrame().feed(RadiacodeProtocol.word(n)); }
        catch(e) { rejected++; }
    }
    Test.assert(rejected==4);
    try { new RadiacodeFrame().feed([4,0,0,0,7,0,0,128,99]b); }
    catch(e) { return true; }
    return false;
}
(:test)
function decodeMixedRecords(logger) {
    var s=RadiacodeProtocol.dataBuffer(Fixtures.reply(),1000);
    Test.assert(s["cps"]==5.5);
    Test.assert(s["dose"]>0.08999 && s["dose"]<0.09001);
    Test.assert(s["timestamp"]==874);
    var first=Fixtures.reply().slice(0,34);
    first.encodeNumber(22,Lang.NUMBER_FORMAT_UINT32,{:offset=>8,:endianness=>Lang.ENDIAN_LITTLE});
    var f=RadiacodeProtocol.dataBuffer(first,1000);
    Test.assert(f["dose"]>0.08699 && f["dose"]<0.08701);
    Test.assert(f["flags"]==0x1234 && f["rtFlags"]==3);
    return true;
}
(:test)
function trailingZeroAndEmpty(logger) {
    var b=Fixtures.reply(); b.add(0);
    Test.assert(RadiacodeProtocol.dataBuffer(b,1000)!=null);
    Test.assert(RadiacodeProtocol.dataBuffer([38,8,0,128,1,0,0,0,0,0,0,0]b,1000)==null);
    b.add(0);
    try { RadiacodeProtocol.dataBuffer(b,1000); } catch(e) { return true; }
    return false;
}
(:test)
function rejectBadRecords(logger) {
    var rejected=0;
    // Bad retcode/length, impossible declared size, NaN and negative CPS.
    // Unknown record IDs are a forward-compatible decoded-prefix boundary.
    for(var variant=0;variant<7;variant++) {
        var b=Fixtures.reply();
        if(variant==0) { b[4]=0; }
        if(variant==1) { b[8]=255; }
        if(variant==2) { b[13]=9; }
        if(variant==3) { b[14]=20; }
        if(variant==4) { b[8]=0; b[9]=0; b[10]=0; b[11]=128; }
        if(variant==5) { b[19]=0; b[20]=0; b[21]=192; b[22]=127; }
        if(variant==6) { b[22]=192; }
        try { RadiacodeProtocol.dataBuffer(b,1000); } catch(e) { rejected++; }
    }
    Test.assert(rejected==5);
    return true;
}
(:test)
function rejectHeaderMismatch(logger) {
    RadiacodeProtocol.checkHeader(Fixtures.reply(),0x826,0);
    try { RadiacodeProtocol.checkHeader(Fixtures.reply(),0x826,1); } catch(e) { return true; }
    return false;
}
(:test)
function firmwareGate(logger) {
    var b=Fixtures.firmware();
    Test.assert(RadiacodeProtocol.firmware(b).equals("4.8"));
    b[12]=7;
    try { RadiacodeProtocol.firmware(b); } catch(e) { return true; }
    return false;
}
(:test)
function truncatedRecords(logger) {
    var good=Fixtures.reply(); var failures=0;
    // Update the declared data length so each truncation reaches the record parser.
    for(var n=13;n<34;n++) {
        var b=good.slice(0,n);
        b.encodeNumber(n-12,Lang.NUMBER_FORMAT_UINT32,{:offset=>8,:endianness=>Lang.ENDIAN_LITTLE});
        try { RadiacodeProtocol.dataBuffer(b,1000); } catch(e) { failures++; }
    }
    Test.assert(failures==21); return true;
}

(:test)
function recordGapKeepsParsingValidatedRecords(logger) {
    var b=Fixtures.reply(); b[34]=7;
    var diagnostics={};
    var sample=RadiacodeProtocol.decodeDataBuffer(b,1000,diagnostics);
    Test.assert(sample["cps"]==5.5);
    Test.assert(sample["timestamp"]==874);
    Test.assert(diagnostics["expected"]==0 && diagnostics["actual"]==7);
    Test.assert(diagnostics["offset"]==22);
    // A raw record before the gap still allows the valid real-time tail.
    b=Fixtures.reply();
    b=b.slice(0,12).addAll(b.slice(34,null));
    b.encodeNumber(b.size()-12,Lang.NUMBER_FORMAT_UINT32,{:offset=>8,:endianness=>Lang.ENDIAN_LITTLE});
    b[27]=99;
    Test.assert(RadiacodeProtocol.dataBuffer(b,1000)!=null);
    return true;
}

(:test)
function unknownRecordKeepsValidatedPrefix(logger) {
    var b=Fixtures.reply();
    // Replace the second record header with a pair observed after a long
    // detector backlog. The valid real-time record before it must survive.
    b[35]=171; b[36]=170;
    var diagnostics={};
    var sample=RadiacodeProtocol.decodeDataBuffer(b,1000,diagnostics);
    Test.assert(sample!=null && sample["cps"]>4.19 && sample["cps"]<4.21);
    Test.assert(diagnostics["unknownEid"]==171 && diagnostics["unknownGid"]==170);
    Test.assert(diagnostics["unknownSeq"]==0 && diagnostics["unknownOffset"]==22);
    return true;
}
