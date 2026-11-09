package com.lenovo.tb321fu.battery;

import java.util.Random;

/**
 * Fake backend with values read from a real TB321FU on 2026-11-09. It keeps protect/limit/bypass
 * state in memory and answers in the same format as herald, so every screen and dialog can be
 * tried without the system patch. Nothing here touches the hardware.
 */
final class DemoBackend implements Backend {
    private final Random rnd = new Random();
    private int level = 82;
    private boolean protect;
    private int protMin = 75;
    private int protMax = 80;
    private int limit = 100;
    private int recharge = 95;
    private boolean bypass;

    @Override
    public synchronized Resp exec(String cmd, long timeoutMs) {
        sleep(120);
        String[] a = cmd.trim().split("\\s+");
        if (a.length < 2 || !a[0].equals("battery")) return Resp.error(cmd, "unknown command");
        String sub = a[1];
        String arg = a.length > 2 ? a[2] : "status";
        switch (sub) {
            case "overview": {
                StringBuilder b = new StringBuilder("ok battery overview\n--- info\n").append(info());
                for (String k : new String[]{"protect", "limit", "bypass"}) {
                    b.append("\n--- ").append(k).append('\n').append(exec("battery " + k + " status", timeoutMs).raw);
                }
                return Resp.parse(cmd, b.toString());
            }
            case "info":
                return Resp.parse(cmd, info());
            case "protect":
                if (arg.equals("on")) {
                    int mn = a.length > 3 ? Resp.parseInt(a[3], -1) : 75;
                    int mx = a.length > 4 ? Resp.parseInt(a[4], -1) : 80;
                    if (mn < 20 || mx > 100 || mn >= mx) return Resp.error(cmd, "usage: protect on <min 20-99> <max>min-100>");
                    protect = true;
                    protMin = mn;
                    protMax = mx;
                    return Resp.parse(cmd, "ok battery protect on\nraw=1\nreadback=1");
                } else if (arg.equals("off")) {
                    protect = false;
                    return Resp.parse(cmd, "ok battery protect off\nraw=0\nreadback=0");
                }
                return Resp.parse(cmd, "ok battery protect\nraw=" + (protect ? 1 : 0) + "\nprotect=" + (protect ? "on" : "off")
                        + "\nmin=" + protMin + "\nmax=" + protMax + "\nremembered=" + protMin + " " + protMax);
            case "limit":
                if (arg.equals("off")) {
                    limit = 100;
                    return Resp.parse(cmd, "ok battery limit off\nraw=100\nreadback=100");
                } else if (!arg.equals("status")) {
                    int l = Resp.parseInt(arg, -1);
                    int r = a.length > 3 ? Resp.parseInt(a[3], -1) : 95;
                    if (l < 20 || l > 100 || r < 50 || r > 100) return Resp.error(cmd, "usage: limit <20-100> [50-100]");
                    limit = l;
                    recharge = r;
                    return Resp.parse(cmd, "ok battery limit\nraw=" + l + "\nreadback=" + l);
                }
                return Resp.parse(cmd, "ok battery limit\nraw=" + limit + "\nfloor=20\nlimit=" + limit
                        + "\nrecharge_raw=" + recharge + "\nremembered=" + limit + " " + recharge);
            case "bypass":
                if (arg.equals("on")) {
                    if (level <= 15) return Resp.error(cmd, "电量 ≤15%, 拒绝开启旁路充电");
                    sleep(3000);
                    bypass = true;
                    return Resp.parse(cmd, "ok battery bypass on\nraw=1\nreadback=1");
                } else if (arg.equals("off")) {
                    sleep(800);
                    bypass = false;
                    return Resp.parse(cmd, "ok battery bypass off\nraw=0\nreadback=0");
                }
                return Resp.parse(cmd, "ok battery bypass\nbypass=" + (bypass ? "on" : "off") + "\ncharger=yes"
                        + "\nbattery_status=" + status() + "\nlevel=" + level);
            default:
                return Resp.error(cmd, "unknown subcommand " + sub);
        }
    }

    private String status() {
        if (bypass) return "Not charging";
        if (level >= Math.min(limit, protect ? protMax : 100)) return level >= 100 ? "Full" : "Not charging";
        return "Charging";
    }

    private String info() {
        boolean charging = status().equals("Charging");
        int cur = charging ? 2400 + rnd.nextInt(300) : (bypass ? -10 - rnd.nextInt(20) : 0);
        StringBuilder b = new StringBuilder("ok battery info\n");
        b.append("level=").append(level).append('\n');
        b.append("status=").append(status()).append('\n');
        b.append("health=Good\n");
        b.append("temp_c=").append(charging ? "31.4" : "28.6").append('\n');
        b.append("voltage_mv=").append(charging ? 4291 : 4180).append('\n');
        b.append("current_ma=").append(cur).append('\n');
        b.append("time_to_full_s=").append(charging ? 2460 : 0).append('\n');
        b.append("time_to_empty_s=0\n");
        b.append("usb_online=1\nwireless_online=0\n");
        cell(b, 1, 261, 95, 286, 4180, cur / 2);
        cell(b, 2, 265, 96, 289, 4182, cur - cur / 2);
        b.append("cells=2\ncycle_max=265\n");
        b.append("soh=95\ncycle_count=265\ncharge_full_uah=5544000\ncharge_full_design_uah=6550000\n");
        return b.toString();
    }

    private static void cell(StringBuilder b, int n, int cyc, int soh, int temp, int mv, int ma) {
        String p = "cell" + n + "_";
        b.append(p).append("cycle_count_raw=").append(cyc).append('\n');
        b.append(p).append("soh_raw=").append(soh).append('\n');
        b.append(p).append("temp_raw=").append(temp).append('\n');
        b.append(p).append("voltage_raw=").append(mv * 1000).append('\n');
        b.append(p).append("current_raw=").append(ma * 1000).append('\n');
        b.append(p).append("activate_date_raw=250330\n");
        b.append(p).append("produce_date_raw=250303\n");
        b.append(p).append("manufacturer=2\n");
    }

    private static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
