package com.lenovo.tb321fu.torch;

/** The app only ever sends `torch apply <1-4>` (allowlisted in herald-apps). */
interface Backend {
    Resp exec(String cmd, long timeoutMs);
}
