// cdump/radiacode types.py and transports/bluetooth.py; see PROTOCOL.md.
module RadiacodeConstants {
    const SERVICE = "e63215e5-7003-49d8-96b0-b024798fb901";
    const WRITE = "e63215e6-7003-49d8-96b0-b024798fb901";
    const NOTIFY = "e63215e7-7003-49d8-96b0-b024798fb901";
    const SET_EXCHANGE = 0x0007;
    const GET_VERSION = 0x000a;
    const SET_TIME = 0x0a04;
    const RD_VIRT_SFR = 0x0824;
    const WR_VIRT_SFR = 0x0825;
    const RD_VIRT_STRING = 0x0826;
    const RD_VIRT_SFR_BATCH = 0x082a;
    const DEVICE_TIME = 0x0504;
    const DATA_BUF = 0x0100;
    const DS_uR = 0x8022;
    const CHUNK_SIZE = 18;
    const MAX_RESPONSE = 8192;
}
