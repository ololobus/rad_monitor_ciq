using Toybox.BluetoothLowEnergy as Ble;
using Toybox.System;

// GATT mechanics only. Session initialization and measurement polling live in Controller.
class RadiacodeBleTransport extends Ble.BleDelegate {
    var _owner; var _device; var _write; var _notify; var _cccd;
    var _registered=false; var _registrationRequested=false; var _active=false; var _tx; var _txPos=0;
    var _writing=false;
    var state="DISCONNECTED";
    var deviceName="";
    var notifications=0;
    function initialize(owner) { BleDelegate.initialize(); _owner=owner; }
    function change(s) { state=s; _owner.onTransportState(s); }
    function start() {
        _active=true;
        try {
            Ble.setDelegate(self);
            if (_registered) { scan(); return; }
            if (_registrationRequested) { fail("Profile pending; reopen app"); return; }
            change("REGISTERING");
            _registrationRequested=true;
            Ble.registerProfile({:uuid=>Ble.stringToUuid(RadiacodeConstants.SERVICE), :characteristics=>[
                {:uuid=>Ble.stringToUuid(RadiacodeConstants.WRITE), :descriptors=>[]},
                {:uuid=>Ble.stringToUuid(RadiacodeConstants.NOTIFY), :descriptors=>[Ble.cccdUuid()]}
            ]});
        } catch (e) { fail("BLE start: " + e.getErrorMessage()); }
    }
    function onProfileRegister(uuid, status) {
        if (status == Ble.STATUS_SUCCESS) { _registered=true; }
        else { _registrationRequested=false; }
        if (!_active) { return; }
        if (status != Ble.STATUS_SUCCESS) { fail("Profile " + status); return; }
        _registered=true; scan();
    }
    function scan() {
        try {
            change("SCANNING");
            System.println("RC available BLE slots=" + Ble.getAvailableConnectionCount());
            Ble.setScanState(Ble.SCAN_STATE_SCANNING);
        } catch (e) { fail("Scan: " + e.getErrorMessage()); }
    }
    function onScanStateChange(scanState, status) {
        if (_active && status != Ble.STATUS_SUCCESS) { fail("Scan status " + status); }
    }
    function onScanResults(results) {
        if (!_active || !state.equals("SCANNING")) { return; }
        for (var r=results.next(); r!=null; r=results.next()) {
            var result=r as Ble.ScanResult;
            var name=result.getDeviceName();
            var identified=name!=null && name.find("RadiaCode") == 0;
            var uuids=result.getServiceUuids();
            for (var uuid=uuids.next(); uuid!=null; uuid=uuids.next()) {
                if (uuid.equals(Ble.stringToUuid(RadiacodeConstants.SERVICE))) { identified=true; }
            }
            if (!identified) { continue; }
            deviceName=name==null ? "Radiacode" : name;
            System.println("RC found " + deviceName + " RSSI=" + result.getRssi());
            try {
                change("CONNECTING");
                Ble.setScanState(Ble.SCAN_STATE_OFF);
                _device=Ble.pairDevice(result);
                if (_device==null) { fail("Pair returned null"); }
            } catch(e) { fail("Pair: " + e.getErrorMessage()); }
            return;
        }
    }
    function onConnectedStateChanged(device, connectionState) {
        if (!_active || state.equals("SCANNING") || state.equals("REGISTERING")) { return; }
        if (connectionState != Ble.CONNECTION_STATE_CONNECTED) {
            fail("Disconnected " + connectionState); return;
        }
        if (!state.equals("CONNECTING")) { return; }
        _device=device;
        try {
            change("DISCOVERING");
            var service=device.getService(Ble.stringToUuid(RadiacodeConstants.SERVICE));
            if (service==null) { fail("Service missing"); return; }
            _write=service.getCharacteristic(Ble.stringToUuid(RadiacodeConstants.WRITE));
            _notify=service.getCharacteristic(Ble.stringToUuid(RadiacodeConstants.NOTIFY));
            if (_write==null || _notify==null) { fail("GATT missing"); return; }
            _cccd=_notify.getDescriptor(Ble.cccdUuid());
            if (_cccd==null) { fail("CCCD missing"); return; }
            change("SUBSCRIBING");
            _cccd.requestWrite([1,0]b);
        } catch(e) { fail("GATT: " + e.getErrorMessage()); }
    }
    function onDescriptorWrite(descriptor, status) {
        if (!_active || !state.equals("SUBSCRIBING")) { return; }
        if (status != Ble.STATUS_SUCCESS) { fail("Subscribe " + status); return; }
        change("INITIALIZING"); _owner.onSubscribed();
    }
    function send(bytes) {
        RadiacodeProtocol.require(!_writing, "Write busy");
        _tx=bytes; _txPos=0; _writing=true; writeNext();
    }
    function writeNext() {
        try {
            var end=_txPos+RadiacodeConstants.CHUNK_SIZE;
            if (end > _tx.size()) { end=_tx.size(); }
            var chunk=_tx.slice(_txPos,end); _txPos=end;
            _write.requestWrite(chunk, {:writeType=>Ble.WRITE_TYPE_DEFAULT});
        } catch(e) { fail("Write: " + e.getErrorMessage()); }
    }
    function onCharacteristicWrite(characteristic, status) {
        if (!_active || !_writing) { return; }
        if (status != Ble.STATUS_SUCCESS) { fail("Write status " + status); return; }
        if (_txPos < _tx.size()) { writeNext(); }
        else { _writing=false; _tx=null; _owner.onWriteComplete(); }
    }
    function onCharacteristicChanged(characteristic, bytes) {
        if (!_active || _notify==null || !characteristic.getUuid().equals(_notify.getUuid())) { return; }
        notifications++; _owner.onBytes(bytes);
    }
    function ready() { change("READY"); }
    function stop() {
        // Explicitly release the detector so it is immediately available to
        // another client after the watch app closes.
        release(true);
    }
    function release(unpair) {
        _active=false; _writing=false; _tx=null;
        try { Ble.setScanState(Ble.SCAN_STATE_OFF); } catch(e) { System.println("RC stop scan: " + e.getErrorMessage()); }
        var old=_device; _device=null; _write=null; _notify=null; _cccd=null;
        if (unpair && old!=null) {
            try { Ble.unpairDevice(old); } catch(e) { System.println("RC unpair: " + e.getErrorMessage()); }
        }
        state="DISCONNECTED";
    }
    function fail(message) {
        release(true); state="ERROR"; _owner.onTransportError(message);
    }
}
