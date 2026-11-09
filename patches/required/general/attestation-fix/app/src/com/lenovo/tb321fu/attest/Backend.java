package com.lenovo.tb321fu.attest;

/**
 * What the app needs from the system. Every call is blocking and is never made on the main thread.
 *
 * The app only ever sends these commands (allowlisted in herald-apps, files/com.lenovo.tb321fu.attest.allow):
 *   get | list | spoof_on PRODUCT | disable
 *   keybox_state | keybox_inspector | keybox_revocation | keybox_import (data in files/herald_keybox_b64_in)
 *   rkp_list | rkp_issue v2 | rkp_import ID
 */
interface Backend {
    Resp exec(String cmd, long timeoutMs);
}
