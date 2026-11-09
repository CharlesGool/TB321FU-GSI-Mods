package com.lenovo.tb321fu.battery;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * One response from the backend, in the herald text format:
 *
 * <pre>
 * ok battery info          (first line: "ok ..." or "err ...")
 * level=85                 (then key=value lines)
 * status=Charging
 * </pre>
 */
final class Resp {
    final String cmd;
    final String raw;
    /** No reply arrived in time. */
    final boolean timeout;
    /** The request was never picked up, which means the backend is not running for this app. */
    final boolean unavailable;

    private final List<String> lines = new ArrayList<>();
    private final Map<String, String> kv = new LinkedHashMap<>();

    Resp(String cmd, String raw, boolean timeout, boolean unavailable) {
        this.cmd = cmd;
        this.raw = raw == null ? "" : raw;
        this.timeout = timeout;
        this.unavailable = unavailable;
        for (String l : this.raw.split("\n")) {
            String t = l.trim();
            if (t.isEmpty()) continue;
            lines.add(t);
            int eq = t.indexOf('=');
            if (eq > 0 && lines.size() > 1) {
                kv.put(t.substring(0, eq).trim(), t.substring(eq + 1).trim());
            }
        }
    }

    static Resp parse(String cmd, String raw) {
        return new Resp(cmd, raw, false, false);
    }

    static Resp error(String cmd, String msg) {
        return new Resp(cmd, "err " + msg, false, false);
    }

    boolean ok() {
        return !lines.isEmpty() && (lines.get(0).equals("ok") || lines.get(0).startsWith("ok "));
    }

    String first() {
        return lines.isEmpty() ? "" : lines.get(0);
    }

    List<String> lines() {
        return Collections.unmodifiableList(lines);
    }

    String kv(String key) {
        String v = kv.get(key);
        return v == null || v.isEmpty() ? null : v;
    }

    int intKv(String key, int def) {
        return parseInt(kv(key), def);
    }

    /** Message to show to the user when ok() is false. */
    String errorText() {
        if (unavailable) return "系统电池服务未响应";
        if (timeout) return "系统电池服务响应超时";
        String f = first();
        if (f.startsWith("err")) f = f.substring(3).trim();
        if (f.startsWith(":")) f = f.substring(1).trim();
        return f.isEmpty() ? "未知错误" : f;
    }

    static int parseInt(String s, int def) {
        if (s == null) return def;
        try {
            return Integer.parseInt(s.trim());
        } catch (NumberFormatException e) {
            try {
                return (int) Math.round(Double.parseDouble(s.trim()));
            } catch (NumberFormatException e2) {
                return def;
            }
        }
    }

    static long parseLong(String s, long def) {
        if (s == null) return def;
        try {
            return Long.parseLong(s.trim());
        } catch (NumberFormatException e) {
            return def;
        }
    }
}
