/*
 * 按 App 伪装 Build.*(herald/app-spoof 模块注入 framework.jar)。
 *
 * 两个入口,都由 framework.jar 的 smali 补丁调用:
 *   init()      ZygoteInit.main 最开头。zygote 以 root 跑,fork App 之前读一次配置,存进静态字段;
 *               fork 出来的 App 进程继承这份内存,不用自己读文件(App 也读不到那个文件)。
 *   setProps()  Instrumentation.newApplication 两个重载的最开头。进程名或包名在名单里,
 *               就用反射把 android.os.Build / Build.VERSION 的静态字段换成配置里的值。
 *
 * 配置文件由 post-fs-data 的伪装脚本写(全局伪装开着才写,关着就删),一行一个:
 *   TARGET=<进程名或包名>          名单,可多行
 *   <字段名>=<值>                  Build 的字段,如 MODEL=Pixel 6a
 *   VERSION.<字段名>=<值>          Build.VERSION 的字段,如 VERSION.SECURITY_PATCH=2026-10-05
 * 系统属性、/system/build.prop 都不动;没在名单里的进程(包括 native 进程、vendor HAL)看到的是真机值。
 * 只改 Java 层字段:名单里的 App 在 native 层直接读系统属性,拿到的仍是真机值。
 */
package com.android.internal.os;

import android.app.Application;
import android.content.Context;
import android.os.Build;

import java.io.BufferedReader;
import java.io.FileReader;
import java.lang.reflect.Field;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

public final class ZygoteCompatHelper {
    private static final String CONF = "/data/system/imitation.conf";

    private static Map<String, String> sBuild;
    private static Map<String, String> sVersion;
    private static Set<String> sTargets;

    private ZygoteCompatHelper() {}

    public static void init() {
        try (BufferedReader r = new BufferedReader(new FileReader(CONF))) {
            Map<String, String> build = new HashMap<>();
            Map<String, String> version = new HashMap<>();
            Set<String> targets = new HashSet<>();
            String line;
            while ((line = r.readLine()) != null) {
                int eq = line.indexOf('=');
                if (eq <= 0) continue;
                String k = line.substring(0, eq);
                String v = line.substring(eq + 1);
                if (v.isEmpty()) continue;
                if (k.equals("TARGET")) targets.add(v);
                else if (k.startsWith("VERSION.")) version.put(k.substring(8), v);
                else build.put(k, v);
            }
            if (targets.isEmpty() || (build.isEmpty() && version.isEmpty())) return;
            sBuild = build;
            sVersion = version;
            sTargets = targets;
        } catch (Throwable ignored) {
            // 文件不存在 = 伪装关着;读失败也按关着处理,不能让 zygote 起不来
        }
    }

    public static void setProps(Context context) {
        Set<String> targets = sTargets;
        if (targets == null || context == null) return;
        try {
            String proc = Application.getProcessName();
            String pkg = context.getPackageName();
            if (!targets.contains(proc) && !targets.contains(pkg)) return;
            apply(Build.class, sBuild);
            apply(Build.VERSION.class, sVersion);
        } catch (Throwable ignored) {
            // 伪装失败也不能让 App 起不来
        }
    }

    private static void apply(Class<?> cls, Map<String, String> values) {
        for (Map.Entry<String, String> e : values.entrySet()) {
            try {
                Field f = cls.getDeclaredField(e.getKey());
                f.setAccessible(true);
                Class<?> t = f.getType();
                if (t == String.class) f.set(null, e.getValue());
                else if (t == int.class) f.setInt(null, Integer.parseInt(e.getValue()));
                else if (t == long.class) f.setLong(null, Long.parseLong(e.getValue()));
            } catch (Throwable ignored) {
                // 某个字段在这个系统版本里不存在或值不合法,跳过,其余照常
            }
        }
    }
}
