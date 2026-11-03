/*
 * 按 App 隐藏开发者选项 / ADB 状态(privacy/devopts-hide 模块注入 framework.jar)。
 *
 * 三个入口,都由 framework.jar 的 smali 补丁调用:
 *   init()      ZygoteInit.main 最开头。zygote 以 root 跑,fork App 之前读一次配置,存进静态字段;
 *               fork 出来的 App 进程继承这份内存,不用自己读文件(App 也读不到那个文件)。
 *   onApp()     Instrumentation.newApplication 两个重载的最开头。进程名或包名命中规则,就把本进程标成"要隐藏"。
 *   over()      Settings$NameValueCache.getStringForUser 的最开头。被标记的进程读到名单里的设置项,直接返回伪装值。
 *
 * 配置文件(privacy/hide-control 写)一行一个:
 *   MODE=list|all        list = 只对 TARGET 里的 App 隐藏;all = 对除 TARGET(白名单)和系统应用以外的所有 App 隐藏
 *   TARGET=<进程名或包名>  可多行
 *   OVER.<设置项>=<值>     被隐藏的进程读这个设置项时看到的值,如 OVER.adb_enabled=0
 * 没有配置文件 = 什么都不做。只改 Java 层的 Settings 读取:native 直接读系统属性、跑 getprop 的 App 看到的仍是真值。
 */
package com.android.internal.os;

import android.app.Application;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.os.Process;

import java.io.BufferedReader;
import java.io.FileReader;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

public final class SettingsCompatHelper {
    private static final String CONF = "/data/system/settings_compat.conf";

    /** 解析后的配置。 */
    static final class Conf {
        boolean all;
        final Set<String> names = new HashSet<>();
        final Map<String, String> over = new HashMap<>();
    }

    private static Conf sConf;                         // zygote 里读好的,App 进程继承
    private static volatile Map<String, String> sHide; // 只在命中规则的 App 进程里非空

    private SettingsCompatHelper() {}

    /** 解析配置行;没有任何伪装项、或 list 模式没有名单,返回 null(= 不启用)。 */
    static Conf parse(List<String> lines) {
        Conf c = new Conf();
        for (String line : lines) {
            int eq = line.indexOf('=');
            if (eq <= 0) continue;
            String k = line.substring(0, eq);
            String v = line.substring(eq + 1);
            if (k.equals("MODE")) c.all = v.equals("all");
            else if (k.equals("TARGET")) { if (!v.isEmpty()) c.names.add(v); }
            else if (k.startsWith("OVER.") && k.length() > 5) c.over.put(k.substring(5), v);
        }
        if (c.over.isEmpty()) return null;
        if (!c.all && c.names.isEmpty()) return null;
        return c;
    }

    /** 该进程是否要隐藏。exempt = 全员模式下免隐藏的系统应用 / 系统 uid。 */
    static boolean hides(Conf c, String proc, String pkg, boolean exempt) {
        boolean listed = (proc != null && c.names.contains(proc)) || (pkg != null && c.names.contains(pkg));
        return c.all ? (!listed && !exempt) : listed;
    }

    public static void init() {
        try (BufferedReader r = new BufferedReader(new FileReader(CONF))) {
            List<String> lines = new ArrayList<>();
            String line;
            while ((line = r.readLine()) != null) lines.add(line);
            sConf = parse(lines);
        } catch (Throwable ignored) {
            // 文件不存在 = 功能关着;读失败也按关着处理,不能让 zygote 起不来
        }
    }

    public static void onApp(Context context) {
        Conf c = sConf;
        if (c == null || context == null) return;
        try {
            boolean exempt = false;
            if (c.all) {
                ApplicationInfo ai = context.getApplicationInfo();
                int sys = ApplicationInfo.FLAG_SYSTEM | ApplicationInfo.FLAG_UPDATED_SYSTEM_APP;
                exempt = Process.myUid() < 10000 || (ai != null && (ai.flags & sys) != 0);
            }
            if (hides(c, Application.getProcessName(), context.getPackageName(), exempt)) sHide = c.over;
        } catch (Throwable ignored) {
            // 判断失败 = 不隐藏,不能让 App 起不来
        }
    }

    public static String over(String name) {
        Map<String, String> m = sHide;
        return (m == null || name == null) ? null : m.get(name);
    }
}
