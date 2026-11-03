/*
 * 状态栏网速显示(net/statusbar-speed 模块注入 framework.jar)。
 *
 * 入口 onApplicationCreate() 由 framework.jar 的 smali 补丁插在 Instrumentation.callApplicationOnCreate 开头调用。
 * 每个 App 进程都会走进来,只有包名是 com.android.systemui 的进程才继续:起一个主线程的定时器(每秒一次),
 * 从 SystemUI 的窗口树里找到状态栏(PhoneStatusBarView),把一个 TextView 插进去。SystemUI 的 APK 一个字节没改,
 * 所以不用动它的(平台)签名。找不到状态栏、反射失败、任何异常都只是不显示,不会让 SystemUI 崩。
 *
 * 设置(Settings.Global,不存在就用默认值;都是字符串):
 *   herald_netspeed       0 关;其他或没设 = 开
 *   herald_netspeed_pos   start = 插在左边时钟后面;其他或没设 = end(右边系统图标前面)
 *   herald_netspeed_mode  both 上下行两行(默认)| down 只显示下行 | total 上下行合计一行(带 ↑↓ 箭头)
 *   herald_netspeed_unit  bits 比特制;其他或没设 = 字节制
 * 数据:TrafficStats.getTotalRxBytes/TxBytes(所有非回环网卡合计;开了 VPN 时隧道和底层网卡会各算一份,速度偏大)。
 * 文字颜色、字体取状态栏时钟的当前值,所以跟着深浅色图标变色。
 */
package com.android.internal.util;

import android.app.Application;
import android.content.ContentResolver;
import android.content.Context;
import android.content.res.Resources;
import android.net.TrafficStats;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.provider.Settings;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.lang.ref.WeakReference;
import java.lang.reflect.Method;

public final class HeraldNetSpeed {
    private static final String TAG = "HeraldNetSpeed";
    private static final String SYSTEMUI = "com.android.systemui";
    private static final String STATUS_BAR_CLASS = "com.android.systemui.statusbar.phone.PhoneStatusBarView";
    private static boolean sStarted;

    private HeraldNetSpeed() {}

    public static void onApplicationCreate(Application app) {
        try {
            if (sStarted || app == null || !SYSTEMUI.equals(app.getPackageName())) return;
            sStarted = true;
            Controller c = new Controller(app);
            c.mHandler.postDelayed(c, 8000);          // 等状态栏窗口建好再说
        } catch (Throwable t) {
            Log.w(TAG, "start failed", t);
        }
    }

    private static final class Controller implements Runnable {
        final Handler mHandler = new Handler(Looper.getMainLooper());
        private final Context mContext;
        private WeakReference<View> mStatusBar;
        private TextView mView;
        private String mAttachedPos;
        private boolean mHaveBase;
        private long mLastRx, mLastTx, mLastT;
        private long mNext = 1000;
        private int mFailures;

        Controller(Context c) { mContext = c; }

        @Override public void run() {
            mNext = 1000;
            try {
                tick();
                mFailures = 0;
            } catch (Throwable t) {
                if (mFailures++ < 3) Log.w(TAG, "tick failed", t);
                mNext = 5000;
            }
            mHandler.postDelayed(this, mNext);
        }

        private String get(String key) {
            try {
                ContentResolver cr = mContext.getContentResolver();
                return Settings.Global.getString(cr, key);
            } catch (Throwable t) {
                return null;
            }
        }

        private void tick() {
            if ("0".equals(get("herald_netspeed"))) {
                detach();
                mHaveBase = false;
                mNext = 3000;
                return;
            }
            View sb = findStatusBar();
            if (sb == null) { mNext = 2000; return; }
            String pos = "start".equals(get("herald_netspeed_pos")) ? "start" : "end";
            if (!ensureView(sb, pos)) { mNext = 3000; return; }
            if (!sb.isShown()) {                      // 熄屏 / 状态栏被隐藏:不采样
                mHaveBase = false;
                mNext = 3000;
                return;
            }
            long rx = TrafficStats.getTotalRxBytes();
            long tx = TrafficStats.getTotalTxBytes();
            long now = SystemClock.elapsedRealtime();
            if (rx < 0 || tx < 0) { mView.setVisibility(View.GONE); mNext = 10000; return; }  // UNSUPPORTED
            long down = 0, up = 0;
            long dt = now - mLastT;
            if (mHaveBase && dt > 0 && dt < 5000) {
                down = Math.max(0, (rx - mLastRx) * 1000 / dt);
                up = Math.max(0, (tx - mLastTx) * 1000 / dt);
            }
            mLastRx = rx; mLastTx = tx; mLastT = now; mHaveBase = true;

            String mode = get("herald_netspeed_mode");
            boolean bits = "bits".equals(get("herald_netspeed_unit"));
            boolean two = !"down".equals(mode) && !"total".equals(mode);
            style(sb, two, bits, "total".equals(mode));
            String text;
            if ("down".equals(mode)) text = "↓" + HeraldNetSpeedFormat.rate(down, bits);
            else if ("total".equals(mode)) text = HeraldNetSpeedFormat.total(down + up, bits);
            else text = HeraldNetSpeedFormat.both(up, down, bits);
            mView.setText(text);
            mView.setVisibility(View.VISIBLE);
        }

        /** 把 TextView 放进状态栏的目标位置;已经在位就什么都不做。返回 false = 现在放不了。 */
        private boolean ensureView(View sb, String pos) {
            Resources res = sb.getResources();
            String containerName = "start".equals(pos) ? "status_bar_start_side_except_heads_up" : "status_bar_end_side_content";
            String anchorName = "start".equals(pos) ? "clock" : "system_icons";
            View c = sb.findViewById(res.getIdentifier(containerName, "id", SYSTEMUI));
            if (!(c instanceof LinearLayout)) return false;
            LinearLayout box = (LinearLayout) c;
            if (mView != null && mView.getParent() == box && pos.equals(mAttachedPos)) return true;
            detach();
            View anchor = sb.findViewById(res.getIdentifier(anchorName, "id", SYSTEMUI));
            int idx = box.getChildCount();
            if (anchor != null && anchor.getParent() == box) {
                idx = box.indexOfChild(anchor) + ("start".equals(pos) ? 1 : 0);
            }
            mView = new TextView(box.getContext());
            mView.setIncludeFontPadding(false);
            mView.setGravity(Gravity.END | Gravity.CENTER_VERTICAL);
            mView.setSingleLine(false);
            mView.setMaxLines(2);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.gravity = Gravity.CENTER_VERTICAL;
            int m = Math.round(TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, 4,
                    res.getDisplayMetrics()));
            lp.setMarginStart(m);
            lp.setMarginEnd(m);
            box.addView(mView, idx, lp);
            mAttachedPos = pos;
            mHaveBase = false;
            return true;
        }

        private void detach() {
            TextView v = mView;
            mView = null;
            mAttachedPos = null;
            if (v != null && v.getParent() instanceof ViewGroup) {
                try { ((ViewGroup) v.getParent()).removeView(v); } catch (Throwable ignored) { }
            }
        }

        /** 字号、颜色、字体跟状态栏时钟走。 */
        private void style(View sb, boolean two, boolean bits, boolean total) {
            View cv = sb.findViewById(sb.getResources().getIdentifier("clock", "id", SYSTEMUI));
            float base = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, 14, sb.getResources().getDisplayMetrics());
            if (cv instanceof TextView) {
                TextView clock = (TextView) cv;
                base = clock.getTextSize();
                mView.setTextColor(clock.getCurrentTextColor());
                if (clock.getTypeface() != null) mView.setTypeface(clock.getTypeface());
            }
            float size = base * (two ? 0.58f : 0.85f);
            if (mView.getTextSize() != size) mView.setTextSize(TypedValue.COMPLEX_UNIT_PX, size);
            mView.setLineSpacing(0f, two ? 0.92f : 1f);
            mView.setMinWidth((int) Math.ceil(mView.getPaint().measureText(total ? "↑" + HeraldNetSpeedFormat.widest(bits) : HeraldNetSpeedFormat.widest(bits))));
        }

        /** 在 SystemUI 的所有窗口里找状态栏(反射 WindowManagerGlobal;framework 自己的代码不受隐藏 API 限制)。 */
        private View findStatusBar() {
            View cached = mStatusBar == null ? null : mStatusBar.get();
            if (cached != null && cached.isAttachedToWindow()) return cached;
            mStatusBar = null;
            try {
                Class<?> wmg = Class.forName("android.view.WindowManagerGlobal");
                Object g = wmg.getMethod("getInstance").invoke(null);
                String[] names = (String[]) wmg.getMethod("getViewRootNames").invoke(g);
                Method getRoot = wmg.getMethod("getRootView", String.class);
                if (names == null) return null;
                for (String n : names) {
                    View root = (View) getRoot.invoke(g, n);
                    View f = root == null ? null : find(root);
                    if (f != null) {
                        mStatusBar = new WeakReference<>(f);
                        return f;
                    }
                }
            } catch (Throwable t) {
                if (mFailures++ < 3) Log.w(TAG, "find status bar failed", t);
            }
            return null;
        }

        private View find(View v) {
            if (STATUS_BAR_CLASS.equals(v.getClass().getName())) return v;
            if (v instanceof ViewGroup) {
                ViewGroup g = (ViewGroup) v;
                for (int i = 0; i < g.getChildCount(); i++) {
                    View f = find(g.getChildAt(i));
                    if (f != null) return f;
                }
            }
            return null;
        }
    }
}
