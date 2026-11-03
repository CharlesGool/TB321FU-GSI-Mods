// SettingsCompatHelper 的解析和命中规则测试(纯 JVM,不碰 Android)。
// 用法: javac -d out SettingsCompatHelper.java HelperTest.java 后 java -cp out com.android.internal.os.HelperTest
package com.android.internal.os;

import java.util.Arrays;
import java.util.List;

public class HelperTest {
    static int pass, fail;
    static void check(String what, boolean cond) { if (cond) pass++; else { fail++; System.out.println("  FAIL: " + what); } }
    static List<String> L(String... s) { return Arrays.asList(s); }

    public static void main(String[] a) throws Exception {
        if (a.length > 0) {   // 集成检查:解析一份真实生成的配置文件,打印摘要(给 toolkit/test-hide-plugin.sh 用)
            SettingsCompatHelper.Conf f = SettingsCompatHelper.parse(java.nio.file.Files.readAllLines(java.nio.file.Paths.get(a[0])));
            System.out.println(f == null ? "null" : "all=" + f.all + " names=" + f.names.size() + " over=" + f.over.size());
            return;
        }
        SettingsCompatHelper.Conf c = SettingsCompatHelper.parse(L("MODE=list", "TARGET=com.bank", "OVER.adb_enabled=0", "OVER.development_settings_enabled=0"));
        check("list 解析", c != null && !c.all && c.names.contains("com.bank") && "0".equals(c.over.get("adb_enabled")) && c.over.size() == 2);
        check("list 命中包名", SettingsCompatHelper.hides(c, "com.other", "com.bank", false));
        check("list 命中进程名", SettingsCompatHelper.hides(c, "com.bank", "com.x", false));
        check("list 不在名单", !SettingsCompatHelper.hides(c, "com.other", "com.other", false));
        check("list 子进程按包名命中", SettingsCompatHelper.hides(c, "com.bank:push", "com.bank", false));
        check("list 子进程只有进程名带后缀且包名不同不命中", !SettingsCompatHelper.hides(c, "com.bank:push", "com.bank2", false));
        check("list 系统应用在名单里也隐藏", SettingsCompatHelper.hides(c, "x", "com.bank", true));

        SettingsCompatHelper.Conf d = SettingsCompatHelper.parse(L("MODE=all", "TARGET=com.keep", "OVER.adb_enabled=0"));
        check("all 解析", d != null && d.all && d.names.size() == 1);
        check("all 普通应用隐藏", SettingsCompatHelper.hides(d, "com.any", "com.any", false));
        check("all 白名单不隐藏", !SettingsCompatHelper.hides(d, "com.keep", "com.keep", false));
        check("all 系统应用免隐藏", !SettingsCompatHelper.hides(d, "com.android.settings", "com.android.settings", true));
        check("all 白名单子进程不隐藏", !SettingsCompatHelper.hides(d, "com.keep:svc", "com.keep", false));
        SettingsCompatHelper.Conf e = SettingsCompatHelper.parse(L("MODE=all", "OVER.adb_enabled=0"));
        check("all 空白名单有效", e != null && e.names.isEmpty() && SettingsCompatHelper.hides(e, "p", "p", false));

        check("没有 OVER 项不启用", SettingsCompatHelper.parse(L("MODE=list", "TARGET=a")) == null);
        check("list 没有名单不启用", SettingsCompatHelper.parse(L("MODE=list", "OVER.adb_enabled=0")) == null);
        check("缺 MODE 当 list", SettingsCompatHelper.parse(L("TARGET=a", "OVER.k=1")) != null && !SettingsCompatHelper.parse(L("TARGET=a", "OVER.k=1")).all);
        check("未知 MODE 当 list", !SettingsCompatHelper.parse(L("MODE=zzz", "TARGET=a", "OVER.k=1")).all);
        check("坏行忽略", SettingsCompatHelper.parse(L("junk", "=x", "TARGET=", "OVER.=1", "TARGET=a", "OVER.k=1")).names.size() == 1);
        check("OVER 值可含等号", "a=b".equals(SettingsCompatHelper.parse(L("TARGET=a", "OVER.k=a=b")).over.get("k")));
        check("未标记进程 over 返回 null", SettingsCompatHelper.over("adb_enabled") == null && SettingsCompatHelper.over(null) == null);

        System.out.println("通过 " + pass + " 项, 失败 " + fail + " 项");
        if (fail > 0) System.exit(1);
    }
}
