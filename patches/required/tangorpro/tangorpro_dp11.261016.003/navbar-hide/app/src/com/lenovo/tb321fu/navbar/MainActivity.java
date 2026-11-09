package com.lenovo.tb321fu.navbar;

import android.app.Activity;
import android.content.Context;
import android.content.res.ColorStateList;
import android.content.res.Configuration;
import android.graphics.Insets;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * 导航栏: one switch, "隐藏导航栏" (herald `navbar hide|show|status`, navbar-hide module).
 * Opened from the gear pages of Settings > System > Navigation mode (three-button / gesture).
 * Hiding only applies in gesture navigation; in three-button mode the wish is remembered and the
 * backend applies it as soon as the user switches to gestures.
 */
public final class MainActivity extends Activity {
    private final Handler ui = new Handler(Looper.getMainLooper());
    private final ExecutorService exec = Executors.newSingleThreadExecutor();
    private Backend backend;
    private Pal pal;
    private ScrollView scroll;
    private PrefGroup errGroup;
    private PrefItem errItem;
    private View mainSection;
    private PrefItem itemHide;
    private View footer;
    private Resp last;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        backend = new HeraldBackend(getApplicationContext());
        build();
    }

    @Override
    public void onConfigurationChanged(Configuration c) {
        super.onConfigurationChanged(c);
        build();
        if (last != null) bind(last);
    }

    @Override
    protected void onResume() {
        super.onResume();
        refresh();
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        exec.shutdown();
    }

    private void build() {
        pal = new Pal(this);
        Context c = this;
        getWindow().getDecorView().setBackgroundColor(pal.surfaceContainer);
        LinearLayout root = new LinearLayout(c);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(pal.surfaceContainer);

        LinearLayout bar = new LinearLayout(c);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setMinimumHeight(Ui.dp(c, 56));
        FrameLayout back = new FrameLayout(c);
        back.setBackground(Ui.ripple(pal, Ui.roundedAll(c, pal.surfaceContainerHighest, 20)));
        back.setClipToOutline(true);
        back.setContentDescription("返回");
        back.setOnClickListener(v -> finish());
        ImageView arrow = new ImageView(c);
        arrow.setImageResource(R.drawable.ic_back);
        arrow.setImageTintList(ColorStateList.valueOf(pal.onSurfaceVariant));
        back.addView(arrow, new FrameLayout.LayoutParams(Ui.dp(c, 16), Ui.dp(c, 16), Gravity.CENTER));
        bar.addView(back, new LinearLayout.LayoutParams(Ui.dp(c, 40), Ui.dp(c, 40)));
        TextView title = Ui.text(c, 22, 28, "variable-title-large-emphasized", 500, pal.onSurface);
        title.setText(R.string.app_name);
        title.setSingleLine(true);
        LinearLayout.LayoutParams tl = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        tl.setMarginStart(Ui.dp(c, 20));
        bar.addView(title, tl);
        root.addView(bar);

        scroll = new ScrollView(c);
        scroll.setClipToPadding(false);
        LinearLayout content = new LinearLayout(c);
        content.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(content, new ScrollView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        root.addView(scroll, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        errGroup = new PrefGroup(c);
        errItem = new PrefItem(c, pal, "无法连接系统导航栏服务");
        errGroup.addItem(errItem);
        errGroup.updateShapes();
        errGroup.setVisibility(View.GONE);
        LinearLayout.LayoutParams el = matchWrap();
        el.topMargin = Ui.dp(c, 16);
        content.addView(errGroup, el);

        PrefGroup g = new PrefGroup(c);
        itemHide = new PrefItem(c, pal, "隐藏导航栏").withSwitch(PrefItem.SWITCH, (item, on) -> toggle(on));
        itemHide.summary("正在读取…");
        g.addItem(itemHide);
        g.updateShapes();
        mainSection = section(content, "手势导航", g);

        footer = buildFooter();
        content.addView(footer, matchWrap());

        root.setOnApplyWindowInsetsListener((v, insets) -> {
            Insets i = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            v.setPadding(i.left, 0, i.right, 0);
            bar.setPaddingRelative(Ui.dp(c, 24), i.top + Ui.dp(c, 8), Ui.dp(c, 24), Ui.dp(c, 8));
            content.setPadding(0, Ui.dp(c, 8), 0, i.bottom + Ui.dp(c, 24));
            return WindowInsets.CONSUMED;
        });
        setContentView(root);
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private View section(LinearLayout parent, String title, PrefGroup group) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        TextView t = Ui.text(this, 14, 20, "variable-title-small", 500, pal.primary);
        t.setText(title);
        t.setAccessibilityHeading(true);
        t.setPaddingRelative(Ui.dp(this, 24), Ui.dp(this, 24), Ui.dp(this, 24), Ui.dp(this, 8));
        box.addView(t, matchWrap());
        box.addView(group, matchWrap());
        parent.addView(box, matchWrap());
        return box;
    }

    private View buildFooter() {
        Context c = this;
        LinearLayout f = new LinearLayout(c);
        f.setOrientation(LinearLayout.VERTICAL);
        f.setPaddingRelative(Ui.dp(c, 24), Ui.dp(c, 24), Ui.dp(c, 24), Ui.dp(c, 8));
        ImageView icon = new ImageView(c);
        icon.setImageResource(R.drawable.ic_info);
        icon.setImageTintList(ColorStateList.valueOf(pal.onSurfaceVariant));
        f.addView(icon, new LinearLayout.LayoutParams(Ui.dp(c, 24), Ui.dp(c, 24)));
        TextView t = Ui.bodyMedium(c, pal);
        t.setText("隐藏后，屏幕底部不再显示手势提示线，应用可以用满整个屏幕。上滑回到主屏幕、上滑停住看最近任务、"
                + "从边缘侧滑返回、沿底部横滑切换应用都和原来一样。\n"
                + "只在手势导航下生效：三按钮导航的按钮需要占位，所以切到三按钮导航时会自动恢复显示，切回手势导航后再自动隐藏。");
        t.setMaxLines(Integer.MAX_VALUE);
        LinearLayout.LayoutParams tl = matchWrap();
        tl.topMargin = Ui.dp(c, 16);
        f.addView(t, tl);
        return f;
    }

    // ------------------------------------------------------------------ data

    private void refresh() {
        exec.execute(() -> {
            Resp r = backend.exec("navbar status", Backend.READ_TIMEOUT_MS);
            ui.post(() -> {
                if (isDestroyed()) return;
                last = r;
                bind(r);
            });
        });
    }

    /** navigation_mode=0(…) → 0; -1 if unknown. */
    private static int navMode(Resp r) {
        String v = r.kv("navigation_mode");
        if (v == null) return -1;
        int i = 0;
        while (i < v.length() && Character.isDigit(v.charAt(i))) i++;
        return i == 0 ? -1 : Resp.parseInt(v.substring(0, i), -1);
    }

    private void bind(Resp r) {
        boolean ok = r.ok();
        Ui.setVisible(errGroup, !ok);
        if (!ok) {
            errItem.summary(r.unavailable
                    ? "这个页面需要系统里的导航栏服务支持。请确认系统已更新到包含它的版本。"
                    : "读取失败：" + r.errorText());
        }
        Ui.setVisible(mainSection, ok);
        Ui.setVisible(footer, ok);
        if (!ok || itemHide.isBusy()) return;
        boolean want = "hide".equals(r.kv("pref"));
        boolean hidden = r.first().startsWith("ok navbar hidden");
        int mode = navMode(r);
        itemHide.setChecked(want, true);
        String sum;
        if (mode == 2) sum = want ? (hidden ? "已隐藏" : "已开启，正在生效…") : "关闭 · 底部显示手势提示线";
        else if (mode >= 0) sum = want ? "已开启 · 切到手势导航后自动隐藏" : "只在手势导航下生效";
        else sum = want ? "已开启" : "关闭";
        itemHide.summary(sum);
    }

    private void toggle(boolean on) {
        itemHide.setChecked(on, true);
        itemHide.summary(on ? "正在隐藏…" : "正在恢复…");
        itemHide.setBusy(true);
        exec.execute(() -> {
            Resp w = backend.exec(on ? "navbar hide" : "navbar show", Backend.WRITE_TIMEOUT_MS);
            Resp s = backend.exec("navbar status", Backend.READ_TIMEOUT_MS);
            ui.post(() -> {
                if (isDestroyed()) return;
                itemHide.setBusy(false);
                last = s;
                bind(s);
                if (!w.ok()) new M3Dialog(this, pal).title("操作失败").message(w.errorText()).button("确定", null).show();
            });
        });
    }
}
