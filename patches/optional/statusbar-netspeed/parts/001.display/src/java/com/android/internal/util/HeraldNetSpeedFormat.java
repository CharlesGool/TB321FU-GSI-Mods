/*
 * 网速文字的格式化(net/statusbar-speed 注入 framework.jar)。纯 Java,不碰 android.*,所以能在电脑上直接测。
 * 字节制:B / KB / MB / GB(1024 进位);比特制:b / Kb / Mb / Gb(1000 进位,按 8 倍换算)。
 * 小于 10 的带一位小数,其余取整;整数档(B)不带小数。例:0B/s、512B/s、1.2MB/s、123KB/s。
 */
package com.android.internal.util;

import java.util.Locale;

public final class HeraldNetSpeedFormat {
    private static final String[] BYTE_UNITS = {"B", "KB", "MB", "GB"};
    private static final String[] BIT_UNITS = {"b", "Kb", "Mb", "Gb"};

    private HeraldNetSpeedFormat() {}

    /** 每秒 bytesPerSec 字节 → 文字。负数当 0。 */
    public static String rate(long bytesPerSec, boolean bits) {
        if (bytesPerSec < 0) bytesPerSec = 0;
        double v = bits ? bytesPerSec * 8.0 : (double) bytesPerSec;
        double base = bits ? 1000.0 : 1024.0;
        String[] units = bits ? BIT_UNITS : BYTE_UNITS;
        int i = 0;
        while (v >= base && i < units.length - 1) {
            v /= base;
            i++;
        }
        String num;
        if (i == 0) num = String.format(Locale.US, "%d", (long) v);
        else if (v < 10) num = String.format(Locale.US, "%.1f", v);
        else num = String.format(Locale.US, "%.0f", v);
        return num + units[i] + "/s";
    }

    /** 两行模式:上行在上,下行在下。 */
    public static String both(long up, long down, boolean bits) {
        return "↑" + rate(up, bits) + "\n↓" + rate(down, bits);
    }

    /** 合计模式:一行,前面带上下行箭头。 */
    public static String total(long sum, boolean bits) {
        return "↑↓" + rate(sum, bits);
    }

    /** 量宽度用的最长样例(固定宽度,数字跳动时旁边的图标不抖)。 */
    public static String widest(boolean bits) {
        return "↓1023" + (bits ? "Kb" : "KB") + "/s";
    }
}
