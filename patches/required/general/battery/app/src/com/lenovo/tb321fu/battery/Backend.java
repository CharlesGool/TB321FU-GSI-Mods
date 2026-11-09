package com.lenovo.tb321fu.battery;

/**
 * What the app needs from the system. Every call is blocking and is never made on the main thread.
 *
 * The app only ever sends these commands (see 后端接口.md):
 *   battery overview   (info + the three status replies in one, "--- <name>" sections)
 *   battery info
 *   battery protect status | on MIN MAX | off
 *   battery limit status | LIMIT RECHARGE | off
 *   battery bypass status | on | off
 *
 * To move to a different transport (binder service, socket, ...), implement this interface and
 * return it from {@link Backends#get}.
 */
interface Backend {
    long READ_TIMEOUT_MS = 6_000;
    /** bypass on blocks for 4-8 s while the backend verifies it. */
    long WRITE_TIMEOUT_MS = 25_000;

    Resp exec(String cmd, long timeoutMs);
}
