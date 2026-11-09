package com.lenovo.tb321fu.navbar;

/**
 * What the app needs from the system. Every call is blocking and is never made on the main thread.
 *
 * The app only ever sends these commands (allowlisted in herald-apps):
 *   navbar status | hide | show
 *
 * To move to a different transport (binder service, socket, ...), implement this interface.
 */
interface Backend {
    long READ_TIMEOUT_MS = 6_000;
    /** hide / show rebuild SystemUI or the launcher: a few seconds. */
    long WRITE_TIMEOUT_MS = 25_000;

    Resp exec(String cmd, long timeoutMs);
}
