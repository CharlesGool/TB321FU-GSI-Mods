package com.lenovo.tb321fu.battery;

import java.util.ArrayList;
import java.util.List;

/** Everything the screen shows, parsed from the four status responses. Missing values are -1 / null. */
final class BatteryState {
    static final int NA = Integer.MIN_VALUE;

    static final class Cell {
        int index;
        int soh = NA;
        int cycles = NA;
        int tempDeci = NA;      // 0.1 C
        int voltageUv = NA;
        int currentUa = NA;
        String produced;        // yyyy-mm-dd
        String activated;
        String manufacturer;
    }

    // battery info
    boolean infoOk;
    String infoError;
    int level = NA;
    String status;              // Charging / Discharging / Not charging / Full
    String health;              // Good / Overheat / ...
    String tempC;
    int voltageMv = NA;
    int currentMa = NA;
    long timeToFullS = -1;
    long timeToEmptyS = -1;
    boolean usb;
    boolean wireless;
    int soh = NA;
    int cycles = NA;
    long fullUah = -1;
    long designUah = -1;
    final List<Cell> cells = new ArrayList<>();

    // battery protect status
    boolean protectOk;
    boolean protectOn;
    int protMin = 75;
    int protMax = 80;

    // battery limit status
    boolean limitOk;
    int limit = 100;
    int recharge = 95;

    // battery bypass status
    boolean bypassOk;
    boolean bypassOn;
    boolean charger;

    /** No reply at all: show the "service unavailable" card. */
    boolean unavailable;

    boolean pluggedIn() {
        return charger || usb || wireless;
    }

    boolean limitOn() {
        return limit < 100;
    }

    /** Level at which charging resumes when the limit is on, as herald computes it. */
    int rechargeLevel() {
        return limit * recharge / 100;
    }

    static BatteryState parse(Resp info, Resp protect, Resp limit, Resp bypass) {
        BatteryState s = new BatteryState();
        s.unavailable = info.unavailable && protect.unavailable && limit.unavailable && bypass.unavailable;

        s.infoOk = info.ok();
        if (s.infoOk) {
            s.level = info.intKv("level", NA);
            s.status = info.kv("status");
            s.health = info.kv("health");
            s.tempC = info.kv("temp_c");
            s.voltageMv = info.intKv("voltage_mv", NA);
            s.currentMa = info.intKv("current_ma", NA);
            s.timeToFullS = Resp.parseLong(info.kv("time_to_full_s"), -1);
            s.timeToEmptyS = Resp.parseLong(info.kv("time_to_empty_s"), -1);
            s.usb = "1".equals(info.kv("usb_online"));
            s.wireless = "1".equals(info.kv("wireless_online"));
            s.fullUah = Resp.parseLong(info.kv("charge_full_uah"), -1);
            s.designUah = Resp.parseLong(info.kv("charge_full_design_uah"), -1);

            int n = info.intKv("cells", 0);
            int minSoh = NA;
            int maxCyc = NA;
            for (int i = 1; i <= n; i++) {
                String p = "cell" + i + "_";
                Cell c = new Cell();
                c.index = i;
                c.soh = info.intKv(p + "soh_raw", NA);
                c.cycles = info.intKv(p + "cycle_count_raw", NA);
                c.tempDeci = info.intKv(p + "temp_raw", NA);
                c.voltageUv = info.intKv(p + "voltage_raw", NA);
                c.currentUa = info.intKv(p + "current_raw", NA);
                c.produced = date(info.kv(p + "produce_date_raw"));
                c.activated = date(info.kv(p + "activate_date_raw"));
                c.manufacturer = info.kv(p + "manufacturer");
                s.cells.add(c);
                if (c.soh != NA && c.soh > 0 && c.soh <= 100) minSoh = minSoh == NA ? c.soh : Math.min(minSoh, c.soh);
                if (c.cycles != NA) maxCyc = Math.max(maxCyc == NA ? 0 : maxCyc, c.cycles);
            }
            // Overall values: prefer what the backend reports for the pack, else derive from the cells.
            s.soh = info.intKv("soh", NA);
            if (s.soh == NA || s.soh <= 0 || s.soh > 100) s.soh = minSoh;
            s.cycles = info.intKv("cycle_count", NA);
            if (s.cycles == NA) s.cycles = info.intKv("cycle_max", maxCyc);
        } else {
            s.infoError = info.errorText();
        }

        s.protectOk = protect.ok();
        if (s.protectOk) {
            s.protectOn = "on".equals(protect.kv("protect"));
            int mn = protect.intKv("min", NA);
            int mx = protect.intKv("max", NA);
            if (mn != NA && mx != NA && mn < mx) {
                s.protMin = mn;
                s.protMax = mx;
            }
        }

        s.limitOk = limit.ok();
        if (s.limitOk) {
            int l = limit.intKv("limit", NA);
            String raw = limit.kv("raw");
            if (l == NA && raw != null && raw.length() >= 3) l = Resp.parseInt(raw.substring(raw.length() - 3), 100);
            if (l == NA) l = 100;
            s.limit = Math.max(20, Math.min(100, l));
            int rc = limit.intKv("recharge_raw", NA);
            if (rc >= 50 && rc <= 100) s.recharge = rc;
        }

        s.bypassOk = bypass.ok();
        if (s.bypassOk) {
            s.bypassOn = "on".equals(bypass.kv("bypass"));
            s.charger = "yes".equals(bypass.kv("charger"));
            if (s.level == NA) s.level = bypass.intKv("level", NA);
        }
        return s;
    }

    /** 250330 -> 2025-03-30 */
    static String date(String raw) {
        if (raw == null) return null;
        String r = raw.trim();
        if (r.length() == 6 && r.chars().allMatch(Character::isDigit)) {
            return "20" + r.substring(0, 2) + "-" + r.substring(2, 4) + "-" + r.substring(4, 6);
        }
        if (r.length() == 8 && r.chars().allMatch(Character::isDigit)) {
            return r.substring(0, 4) + "-" + r.substring(4, 6) + "-" + r.substring(6, 8);
        }
        return r.isEmpty() || r.equals("0") ? null : r;
    }
}
