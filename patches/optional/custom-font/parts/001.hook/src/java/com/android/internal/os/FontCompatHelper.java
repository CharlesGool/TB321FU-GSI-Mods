/*
 * 自定义系统字体(font/custom-font 模块注入 framework.jar)。
 *
 * 入口由 SystemFonts.getSystemFontConfigInternal 开头的 smali 补丁调用(system_server 的 FontManagerService 建字体表时走这里):
 *   xml(stock) / dir(stock) / oem(stock) / pdir(stock)
 *     分别对应它的四个路径参数(fontsXml、systemFontDir、oemXml、productFontDir)。
 *     有可用的字体包就返回包里的路径,没有就原样返回 stock。四个方法给出的结论一致(同一个进程里只判断一次)。
 *
 * 字体包放在 /data/fonts/herald/packs/<名字>/,当前用哪个写在 /data/fonts/herald/active(一行名字)。包里:
 *   font_fallback.xml        必须有;字体文件都放在同一个目录里(没改的系统字体由 font-control 做成指向 /system/fonts 的符号链接)
 *   fonts_customization.xml  可选;有就替换 /product/etc/fonts_customization.xml(Google Sans 之类),字体目录同样是包目录
 * 判断"可用"要过三关:文件都读得到;用系统自己的 FontListParser 试解析一次(反射,本类在 boot classpath 里不受隐藏 API 限制),
 * 不抛异常且字体族不为空;任何一步失败都回到系统原配置,不能让 system_server 起不来。
 */
package com.android.internal.os;

import java.io.File;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Collections;
import java.util.List;
import java.util.Map;

public final class FontCompatHelper {
    private static final String ROOT = "/data/fonts/herald";

    private static boolean sDecided;
    private static String sDir;       // 包目录(以 / 结尾);null = 用系统原配置
    private static String sOem;       // 包里的 fonts_customization.xml;null = 用系统原来的

    private FontCompatHelper() {}

    /** 包名合法:字母数字 . _ -,不以点开头,不含 ..;避免 active 文件被写成路径跳出 packs/。 */
    static boolean nameOk(String n) {
        if (n == null || n.isEmpty() || n.length() > 64 || n.startsWith(".") || n.contains("..")) return false;
        for (int i = 0; i < n.length(); i++) {
            char c = n.charAt(i);
            boolean ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-';
            if (!ok) return false;
        }
        return true;
    }

    private static synchronized void decide(String stockXml, String stockOem) {
        if (sDecided) return;
        sDecided = true;
        try {
            File active = new File(ROOT, "active");
            if (!active.isFile()) return;
            String name = new String(Files.readAllBytes(active.toPath()), StandardCharsets.UTF_8).trim();
            if (!nameOk(name)) return;
            File dir = new File(ROOT + "/packs/" + name);
            File xml = new File(dir, "font_fallback.xml");
            if (!dir.isDirectory() || !xml.isFile() || !xml.canRead()) return;
            File oem = new File(dir, "fonts_customization.xml");
            String oemPath = oem.isFile() && oem.canRead() ? oem.getPath() : null;
            String d = dir.getPath() + "/";
            if (!parses(xml.getPath(), d, oemPath != null ? oemPath : stockOem, oemPath != null ? d : null)) return;
            sDir = d;
            sOem = oemPath;
        } catch (Throwable ignored) {
            // 任何问题都按没有字体包处理
        }
    }

    /** 用系统自己的解析器试一遍:不抛异常、字体族非空才算可用。 */
    private static boolean parses(String xml, String dir, String oem, String pdir) {
        try {
            Class<?> p = Class.forName("android.graphics.FontListParser");
            Method m = p.getDeclaredMethod("parse", String.class, String.class, String.class, String.class,
                    Map.class, long.class, int.class);
            m.setAccessible(true);
            Object cfg = m.invoke(null, xml, dir, oem, pdir == null ? "/product/fonts/" : pdir,
                    Collections.emptyMap(), 0L, 0);
            if (cfg == null) return false;
            Object fams = cfg.getClass().getMethod("getFontFamilies").invoke(cfg);
            Object named = cfg.getClass().getMethod("getNamedFamilyLists").invoke(cfg);
            return fams instanceof List && !((List<?>) fams).isEmpty() && named instanceof List && !((List<?>) named).isEmpty();
        } catch (Throwable t) {
            return false;
        }
    }

    public static String xml(String stock) {
        try {
            decide(stock, null);
            return sDir != null ? sDir + "font_fallback.xml" : stock;
        } catch (Throwable t) {
            return stock;
        }
    }

    public static String dir(String stock) {
        return sDir != null ? sDir : stock;
    }

    public static String oem(String stock) {
        return sDir != null && sOem != null ? sOem : stock;
    }

    public static String pdir(String stock) {
        return sDir != null && sOem != null ? sDir : stock;
    }
}
