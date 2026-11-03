// FontCompatHelper 的包名校验测试(纯 JVM)。xml/dir/oem/pdir 依赖 /data 和系统解析器,只验证"没有字体包时原样返回"。
package com.android.internal.os;

public class FontHelperTest {
    static int pass, fail;
    static void check(String what, boolean cond) { if (cond) pass++; else { fail++; System.out.println("  FAIL: " + what); } }

    public static void main(String[] a) {
        check("普通名字", FontCompatHelper.nameOk("MyFont"));
        check("带点横线下划线数字", FontCompatHelper.nameOk("lxgw-wenkai_2.1"));
        check("空", !FontCompatHelper.nameOk(""));
        check("null", !FontCompatHelper.nameOk(null));
        check("斜杠", !FontCompatHelper.nameOk("a/b"));
        check("上级目录", !FontCompatHelper.nameOk("..") && !FontCompatHelper.nameOk("a..b"));
        check("点开头", !FontCompatHelper.nameOk(".hidden"));
        check("空格", !FontCompatHelper.nameOk("a b"));
        check("中文", !FontCompatHelper.nameOk("字体"));
        check("太长", !FontCompatHelper.nameOk("x".repeat(65)) && FontCompatHelper.nameOk("x".repeat(64)));
        check("无字体包 xml 原样", "/system/etc/font_fallback.xml".equals(FontCompatHelper.xml("/system/etc/font_fallback.xml")));
        check("无字体包 dir 原样", "/system/fonts/".equals(FontCompatHelper.dir("/system/fonts/")));
        check("无字体包 oem 原样", "/product/etc/fonts_customization.xml".equals(FontCompatHelper.oem("/product/etc/fonts_customization.xml")));
        check("无字体包 pdir 原样", "/product/fonts/".equals(FontCompatHelper.pdir("/product/fonts/")));
        System.out.println("通过 " + pass + " 项, 失败 " + fail + " 项");
        if (fail > 0) System.exit(1);
    }
}
