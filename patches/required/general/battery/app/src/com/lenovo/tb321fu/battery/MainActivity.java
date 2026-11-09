package com.lenovo.tb321fu.battery;

import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.res.ColorStateList;
import android.content.res.Configuration;
import android.graphics.Insets;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.TextView;

import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * 电池管理: battery health (pack and each cell), live status, and charging controls
 * (charge limit, long-term plug-in protection, bypass charging).
 *
 * Opened from the tile Settings injects into Settings > Battery. Laid out to match the
 * Android 16 expressive Settings pages: grouped rounded cards on surfaceContainer.
 */
public final class MainActivity extends Activity {
    static final String PREFS = "battery";
    static final String KEY_SUMMARY = "tile_summary";
    private static final String KEY_LAST_LIMIT = "last_limit";
    private static final String KEY_LAST_RECHARGE = "last_recharge";
    /** Raw text of the last successful "battery overview", shown at once on the next open. */
    private static final String KEY_LAST_OVERVIEW = "last_overview";
    private static final long REFRESH_MS = 5_000;

    private final Handler ui = new Handler(Looper.getMainLooper());
    private final ExecutorService exec = Executors.newSingleThreadExecutor();
    private Backend backend;
    private boolean demo;
    private Pal pal;
    private SharedPreferences prefs;
    private boolean resumed;
    private int loopGen;
    private BatteryState state;

    // Views
    private TextView toolbarTitle;
    private ScrollView scroll;
    private TextView heroLevel;
    private TextView heroStatus;
    private TextView heroNote;
    private LevelBar heroBar;
    private PrefGroup errGroup;
    private PrefItem errItem;
    private View healthSection;
    private PrefItem itemSoh;
    private PrefItem itemCapacity;
    private PrefItem itemCycles;
    private PrefItem itemCondition;
    private View cellsSection;
    private PrefGroup cellsGroup;
    private CellCard[] cellCards = new CellCard[0];
    private View liveSection;
    private PrefItem itemTemp;
    private PrefItem itemVoltage;
    private PrefItem itemCurrent;
    private PrefItem itemSource;
    private View chargeSection;
    private PrefGroup chargeGroup;
    private PrefItem itemLimit;
    private PrefItem itemProtect;
    private PrefItem itemBypass;
    private PrefGroup healthGroup;
    private PrefGroup liveGroup;
    private View footer;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        demo = getIntent().getBooleanExtra("demo", false);
        backend = Backends.get(this, demo);
        prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        build();
        // Show what we read last time right away; the first refresh replaces it in a second or two.
        String cached = demo ? null : prefs.getString(KEY_LAST_OVERVIEW, null);
        if (cached != null) {
            BatteryState s = fromOverview(Resp.parse("battery overview", cached));
            if (s != null && s.infoOk) {
                state = s;
                bind(s);
            }
        }
    }

    @Override
    public void onConfigurationChanged(Configuration c) {
        super.onConfigurationChanged(c);
        int y = scroll == null ? 0 : scroll.getScrollY();
        build();
        if (state != null) bind(state);
        scroll.post(() -> scroll.scrollTo(0, y));
    }

    @Override
    protected void onResume() {
        super.onResume();
        resumed = true;
        startLoop();
    }

    @Override
    protected void onPause() {
        super.onPause();
        resumed = false;
        loopGen++;
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        exec.shutdown();
    }

    // ------------------------------------------------------------------ layout

    private void build() {
        pal = new Pal(this);
        Context c = this;
        getWindow().getDecorView().setBackgroundColor(pal.surfaceContainer);

        LinearLayout root = new LinearLayout(c);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(pal.surfaceContainer);

        // Toolbar: 40dp back circle + title, as in Settings.
        LinearLayout bar = new LinearLayout(c);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setMinimumHeight(Ui.dp(c, 56));
        bar.setPaddingRelative(Ui.dp(c, 24), Ui.dp(c, 8), Ui.dp(c, 24), Ui.dp(c, 8));
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
        toolbarTitle = Ui.text(c, 22, 28, "variable-title-large-emphasized", 500, pal.onSurface);
        toolbarTitle.setText(R.string.app_name);
        toolbarTitle.setSingleLine(true);
        LinearLayout.LayoutParams tl = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        tl.setMarginStart(Ui.dp(c, 20));
        bar.addView(toolbarTitle, tl);
        root.addView(bar);

        scroll = new ScrollView(c);
        scroll.setClipToPadding(false);
        scroll.setVerticalScrollBarEnabled(false);
        LinearLayout content = new LinearLayout(c);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(0, Ui.dp(c, 8), 0, Ui.dp(c, 24));
        scroll.addView(content, new ScrollView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        root.addView(scroll, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        // Hero: level and charging status, laid out like the Settings battery header.
        content.addView(buildHero(), matchWrap());

        // Service unavailable.
        errGroup = new PrefGroup(c);
        errItem = new PrefItem(c, pal, "无法连接系统电池服务");
        errGroup.addItem(errItem);
        errGroup.updateShapes();
        errGroup.setVisibility(View.GONE);
        LinearLayout.LayoutParams el = matchWrap();
        el.topMargin = Ui.dp(c, 16);
        content.addView(errGroup, el);

        // 电池健康
        healthGroup = new PrefGroup(c);
        itemSoh = new PrefItem(c, pal, "电池健康度");
        itemCapacity = new PrefItem(c, pal, "满电容量");
        itemCycles = new PrefItem(c, pal, "充电循环次数");
        itemCondition = new PrefItem(c, pal, "电池状态");
        healthGroup.addItem(itemSoh);
        healthGroup.addItem(itemCapacity);
        healthGroup.addItem(itemCycles);
        healthGroup.addItem(itemCondition);
        healthSection = section(content, "电池健康", healthGroup);

        // 电池 1 / 电池 2
        cellsGroup = new PrefGroup(c);
        cellsSection = section(content, "电芯", cellsGroup);
        cellCards = new CellCard[0];

        // 实时状态
        liveGroup = new PrefGroup(c);
        itemTemp = new PrefItem(c, pal, "温度");
        itemVoltage = new PrefItem(c, pal, "电压");
        itemCurrent = new PrefItem(c, pal, "电流");
        itemSource = new PrefItem(c, pal, "电源");
        liveGroup.addItem(itemTemp);
        liveGroup.addItem(itemVoltage);
        liveGroup.addItem(itemCurrent);
        liveGroup.addItem(itemSource);
        liveSection = section(content, "实时状态", liveGroup);

        // 充电
        chargeGroup = new PrefGroup(c);
        itemLimit = new PrefItem(c, pal, "充电上限").withSwitch(PrefItem.PRIMARY_SWITCH, this::toggleLimit);
        itemLimit.setOnClickListener(v -> showLimitDialog());
        itemProtect = new PrefItem(c, pal, "长期插电保护").withSwitch(PrefItem.PRIMARY_SWITCH, this::toggleProtect);
        itemProtect.setOnClickListener(v -> showProtectDialog());
        itemBypass = new PrefItem(c, pal, "旁路充电").withSwitch(PrefItem.SWITCH, this::toggleBypass);
        chargeGroup.addItem(itemLimit);
        chargeGroup.addItem(itemProtect);
        chargeGroup.addItem(itemBypass);
        chargeSection = section(content, "充电", chargeGroup);

        footer = buildFooter();
        content.addView(footer, matchWrap());

        for (View v : new View[]{healthSection, cellsSection, liveSection, chargeSection, footer}) {
            v.setVisibility(View.GONE);
        }
        healthGroup.updateShapes();
        liveGroup.updateShapes();
        chargeGroup.updateShapes();

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

    /** Category title (TitleSmall in primary, 24dp from the edge) followed by its group. */
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

    /**
     * Same layout as the header of Settings > Battery: big level number with a small "%",
     * a 40dp rounded level bar inset 16dp, and the status line below it, all on the window
     * background (no card).
     */
    private View buildHero() {
        Context c = this;
        LinearLayout box = new LinearLayout(c);
        box.setOrientation(LinearLayout.VERTICAL);

        heroLevel = Ui.text(c, 57, 56, "variable-display-large-emphasized", 500, pal.onSurface);
        heroLevel.setText("--");
        heroLevel.setPaddingRelative(Ui.dp(c, 24), 0, Ui.dp(c, 24), 0);
        box.addView(heroLevel, matchWrap());

        heroBar = new LevelBar(c, pal, 40);
        LinearLayout.LayoutParams bl = matchWrap();
        bl.topMargin = Ui.dp(c, 6);
        bl.setMarginStart(Ui.dp(c, 16));
        bl.setMarginEnd(Ui.dp(c, 16));
        box.addView(heroBar, bl);

        heroStatus = Ui.bodyMedium(c, pal);
        heroStatus.setText("正在读取…");
        heroStatus.setPaddingRelative(Ui.dp(c, 24), Ui.dp(c, 14), Ui.dp(c, 24), 0);
        box.addView(heroStatus, matchWrap());

        heroNote = Ui.bodyMedium(c, pal);
        heroNote.setVisibility(View.GONE);
        heroNote.setPaddingRelative(Ui.dp(c, 24), Ui.dp(c, 2), Ui.dp(c, 24), 0);
        box.addView(heroNote, matchWrap());
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
        t.setText("充电上限：电量到上限后停止充电，降到“上限 × 恢复比例”以下时再开始充电。\n"
                + "长期插电保护：一直插着电时，把电量维持在设定的区间内，减缓电池老化。\n"
                + "旁路充电：接着充电器时由充电器直接给平板供电，电池既不充也不放，适合边充边玩。电量不高于 15% 时无法开启。\n"
                + "健康度、循环次数等数据来自电池电量计，仅供参考。");
        t.setMaxLines(Integer.MAX_VALUE);
        LinearLayout.LayoutParams tl = matchWrap();
        tl.topMargin = Ui.dp(c, 16);
        f.addView(t, tl);
        return f;
    }

    /** One battery cell: name, health, and a 3x2 grid of readings. */
    private final class CellCard extends Shaped {
        final TextView name;
        final TextView sub;
        final TextView soh;
        final LevelBar bar;
        final TextView[] values = new TextView[6];
        static final int CYCLES = 0, TEMP = 1, VOLT = 2, CURR = 3, MADE = 4, ACTIVE = 5;

        CellCard(Context c, Pal p, int index) {
            super(c, p);
            setOrientation(VERTICAL);
            setPaddingRelative(Ui.dp(c, 16), Ui.dp(c, 16), Ui.dp(c, 16), Ui.dp(c, 16));

            LinearLayout head = new LinearLayout(c);
            head.setGravity(Gravity.CENTER_VERTICAL);
            LinearLayout names = new LinearLayout(c);
            names.setOrientation(VERTICAL);
            name = Ui.titleMedium(c, pal);
            name.setText("电池 " + index);
            sub = Ui.bodyMedium(c, pal);
            sub.setVisibility(GONE);
            names.addView(name);
            names.addView(sub);
            head.addView(names, new LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
            LinearLayout right = new LinearLayout(c);
            right.setOrientation(VERTICAL);
            right.setGravity(Gravity.END);
            soh = Ui.text(c, 28, 36, "variable-headline-medium-emphasized", 500, pal.primary);
            TextView sohLabel = Ui.text(c, 12, 16, "variable-label-medium", 500, pal.onSurfaceVariant);
            sohLabel.setText("健康度");
            right.addView(soh);
            right.addView(sohLabel);
            head.addView(right);
            addView(head, matchWrap());

            bar = new LevelBar(c, pal, 6);
            LayoutParams bl = matchWrap();
            bl.topMargin = Ui.dp(c, 12);
            addView(bar, bl);

            String[] labels = {"循环次数", "温度", "电压", "电流", "生产日期", "激活日期"};
            for (int row = 0; row < 2; row++) {
                LinearLayout r = new LinearLayout(c);
                for (int col = 0; col < 3; col++) {
                    int i = row * 3 + col;
                    LinearLayout cellBox = new LinearLayout(c);
                    cellBox.setOrientation(VERTICAL);
                    TextView l = Ui.text(c, 12, 16, "variable-body-small", 400, pal.onSurfaceVariant);
                    l.setText(labels[i]);
                    values[i] = Ui.text(c, 16, 24, "variable-title-medium", 500, pal.onSurface);
                    values[i].setText("—");
                    values[i].setSingleLine(true);
                    cellBox.addView(l);
                    cellBox.addView(values[i]);
                    r.addView(cellBox, new LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
                }
                LayoutParams rl = matchWrap();
                rl.topMargin = Ui.dp(c, row == 0 ? 16 : 12);
                addView(r, rl);
            }
        }

        void bind(BatteryState.Cell cell) {
            soh.setText(cell.soh == BatteryState.NA ? "—" : cell.soh + "%");
            bar.set(cell.soh == BatteryState.NA ? 0 : cell.soh, -1);
            bar.setIndicatorColor(cell.soh != BatteryState.NA && cell.soh < 80 ? pal.error : pal.primary);
            soh.setTextColor(cell.soh != BatteryState.NA && cell.soh < 80 ? pal.error : pal.primary);
            values[CYCLES].setText(cell.cycles == BatteryState.NA ? "—" : cell.cycles + " 次");
            values[TEMP].setText(cell.tempDeci == BatteryState.NA ? "—" : fmtDeci(cell.tempDeci) + " ℃");
            values[VOLT].setText(cell.voltageUv == BatteryState.NA ? "—" : String.format(Locale.ROOT, "%.3f V", cell.voltageUv / 1e6));
            values[CURR].setText(cell.currentUa == BatteryState.NA ? "—" : fmtMa(cell.currentUa / 1000));
            values[MADE].setText(cell.produced == null ? "—" : cell.produced);
            values[ACTIVE].setText(cell.activated == null ? "—" : cell.activated);
            // The fuel gauge only reports a bare vendor code (e.g. 2) with no name behind it: not shown.
            Ui.setVisible(sub, false);
        }
    }

    private void ensureCellCards(int n) {
        if (cellCards.length == n) return;
        cellsGroup.removeAllViews();
        cellCards = new CellCard[n];
        boolean wide = getResources().getConfiguration().screenWidthDp >= 600 && n == 2;
        PrefGroup.Row row = wide ? new PrefGroup.Row(this) : null;
        for (int i = 0; i < n; i++) {
            cellCards[i] = new CellCard(this, pal, i + 1);
            if (row != null) row.addCard(cellCards[i]);
            else cellsGroup.addItem(cellCards[i]);
        }
        if (row != null) cellsGroup.addItem(row);
        cellsGroup.updateShapes();
    }

    // ------------------------------------------------------------------ data

    private void startLoop() {
        final int gen = ++loopGen;
        refreshOnce(() -> {
            if (resumed && gen == loopGen) ui.postDelayed(() -> {
                if (resumed && gen == loopGen) startLoopContinue(gen);
            }, REFRESH_MS);
        });
    }

    private void startLoopContinue(int gen) {
        refreshOnce(() -> {
            if (resumed && gen == loopGen) ui.postDelayed(() -> {
                if (resumed && gen == loopGen) startLoopContinue(gen);
            }, REFRESH_MS);
        });
    }

    /** Reads everything on the backend thread, then binds on the main thread and runs {@code then}. */
    private void refreshOnce(Runnable then) {
        exec.execute(() -> {
            // One request for everything (battery overview); older systems without it get four.
            Resp all = backend.exec("battery overview", Backend.READ_TIMEOUT_MS);
            BatteryState s = all.ok() ? fromOverview(all) : null;
            if (s != null && s.infoOk && !demo) prefs.edit().putString(KEY_LAST_OVERVIEW, all.raw).apply();
            if (s == null) {
                Resp info = all.unavailable ? all : backend.exec("battery info", Backend.READ_TIMEOUT_MS);
                Resp protect, limit, bypass;
                if (info.unavailable) {
                    protect = limit = bypass = info;
                } else {
                    protect = backend.exec("battery protect status", Backend.READ_TIMEOUT_MS);
                    limit = backend.exec("battery limit status", Backend.READ_TIMEOUT_MS);
                    bypass = backend.exec("battery bypass status", Backend.READ_TIMEOUT_MS);
                }
                s = BatteryState.parse(info, protect, limit, bypass);
            }
            final BatteryState fs = s;
            ui.post(() -> {
                if (isDestroyed()) return;
                // Keep showing the last good data if one refresh fails (e.g. a slow write is running).
                boolean anyOk = fs.infoOk || fs.protectOk || fs.limitOk || fs.bypassOk;
                if (anyOk || state == null || !(state.infoOk || state.protectOk)) {
                    state = fs;
                    bind(fs);
                    saveSummary(fs);
                }
                if (then != null) then.run();
            });
        });
    }

    /**
     * Splits "battery overview" ("--- info", "--- protect", "--- limit", "--- bypass" sections,
     * each the plain reply of that command) and parses it. null if it is not an overview reply.
     */
    static BatteryState fromOverview(Resp all) {
        if (!all.ok() || !all.first().startsWith("ok battery overview")) return null;
        java.util.Map<String, StringBuilder> sec = new java.util.HashMap<>();
        StringBuilder cur = null;
        for (String l : all.raw.split("\n")) {
            if (l.startsWith("--- ")) {
                cur = new StringBuilder();
                sec.put(l.substring(4).trim(), cur);
            } else if (cur != null) {
                cur.append(l).append('\n');
            }
        }
        if (!sec.containsKey("info")) return null;
        java.util.function.Function<String, Resp> r = k -> sec.containsKey(k)
                ? Resp.parse("battery " + k, sec.get(k).toString())
                : Resp.error("battery " + k, "系统里没有这个功能");
        return BatteryState.parse(r.apply("info"), r.apply("protect"), r.apply("limit"), r.apply("bypass"));
    }

    private void bind(BatteryState s) {
        boolean anyOk = s.infoOk || s.protectOk || s.limitOk || s.bypassOk;

        // Unavailable / error card
        if (!anyOk) {
            errItem.summary(s.unavailable
                    ? "这个页面需要系统里的电池服务支持。请确认系统已更新到包含电池管理的版本。"
                    : "读取失败：" + (s.infoError == null ? "未知错误" : s.infoError));
        }
        Ui.setVisible(errGroup, !anyOk);

        // Hero
        if (s.level != BatteryState.NA) {
            android.text.SpannableString t = new android.text.SpannableString(s.level + "%");
            t.setSpan(new android.text.style.AbsoluteSizeSpan(16, true), t.length() - 1, t.length(), 0);
            heroLevel.setText(t);
        } else {
            heroLevel.setText("--");
        }
        heroStatus.setText(anyOk ? statusLine(s) : "无法读取电池信息");
        int marker = s.limitOk && s.limitOn() ? s.limit : (s.protectOk && s.protectOn ? s.protMax : -1);
        heroBar.set(s.level == BatteryState.NA ? 0 : s.level, marker);
        String note = null;
        if (s.bypassOn) note = "旁路充电已开启：充电器直接为平板供电";
        else if (s.limitOk && s.limitOn()) note = "充电上限 " + s.limit + "%";
        else if (s.protectOk && s.protectOn) note = "长期插电保护 " + s.protMin + "%–" + s.protMax + "%";
        heroNote.setText(note);
        Ui.setVisible(heroNote, note != null);

        // Health
        Ui.setVisible(healthSection, s.infoOk);
        if (s.infoOk) {
            itemSoh.value(s.soh == BatteryState.NA ? "—" : s.soh + "%");
            itemSoh.summary(s.soh == BatteryState.NA ? "电量计没有提供健康度"
                    : s.soh >= 80 ? "相对新电池的最大容量，电池状况良好"
                    : "电池容量已明显下降，续航会变短");
            boolean cap = s.fullUah > 0;
            Ui.setVisible(itemCapacity, cap);
            if (cap) {
                itemCapacity.value(mah(s.fullUah));
                itemCapacity.summary(s.designUah > 0
                        ? String.format(Locale.ROOT, "设计容量 %s，当前为设计容量的 %.1f%%", mah(s.designUah), 100.0 * s.fullUah / s.designUah)
                        : null);
            }
            itemCycles.value(s.cycles == BatteryState.NA ? "—" : s.cycles + " 次");
            itemCycles.summary(s.cells.size() > 1 ? "取各电芯中的最大值" : null);
            itemCondition.value(healthName(s.health));
            healthGroup.updateShapes();
        }

        // Cells
        Ui.setVisible(cellsSection, s.infoOk && !s.cells.isEmpty());
        if (s.infoOk && !s.cells.isEmpty()) {
            ensureCellCards(s.cells.size());
            for (int i = 0; i < cellCards.length; i++) cellCards[i].bind(s.cells.get(i));
        }

        // Live
        Ui.setVisible(liveSection, s.infoOk);
        if (s.infoOk) {
            itemTemp.value(s.tempC == null ? "—" : s.tempC + " ℃");
            itemVoltage.value(s.voltageMv == BatteryState.NA ? "—" : String.format(Locale.ROOT, "%.3f V", s.voltageMv / 1000.0));
            itemCurrent.value(s.currentMa == BatteryState.NA ? "—" : fmtMa(s.currentMa));
            String src = s.wireless ? "无线充电" : (s.usb || s.charger) ? "USB 电源" : "电池";
            itemSource.value(src);
            liveGroup.updateShapes();
        }

        // Charging controls
        Ui.setVisible(chargeSection, anyOk);
        bindLimit(s);
        bindProtect(s);
        bindBypass(s);
        chargeGroup.updateShapes();
        Ui.setVisible(footer, anyOk);
    }

    private void bindLimit(BatteryState s) {
        itemLimit.setRowEnabled(s.limitOk);
        if (itemLimit.isBusy()) return;
        itemLimit.setChecked(s.limitOn(), true);
        itemLimit.summary(!s.limitOk ? "无法读取"
                : s.limitOn() ? "充到 " + s.limit + "% 时停止，降到 " + s.rechargeLevel() + "% 以下再充电"
                : "关闭 · 正常充到 100%");
    }

    private void bindProtect(BatteryState s) {
        itemProtect.setRowEnabled(s.protectOk);
        if (itemProtect.isBusy()) return;
        itemProtect.setChecked(s.protectOn, true);
        itemProtect.summary(!s.protectOk ? "无法读取"
                : s.protectOn ? "插着电时电量保持在 " + s.protMin + "%–" + s.protMax + "%"
                : "关闭 · 长时间插电时把电量维持在设定区间");
    }

    private void bindBypass(BatteryState s) {
        if (itemBypass.isBusy()) return;
        boolean lowBattery = s.level != BatteryState.NA && s.level <= 15;
        boolean canEnable = s.bypassOk && (s.bypassOn || (s.pluggedIn() && !lowBattery));
        itemBypass.setRowEnabled(canEnable);
        itemBypass.setChecked(s.bypassOn, true);
        String sum;
        if (!s.bypassOk) sum = "无法读取";
        else if (s.bypassOn) sum = "已开启 · 充电器直接为平板供电，电池不充不放";
        else if (!s.pluggedIn()) sum = "连接充电器后可开启";
        else if (lowBattery) sum = "电量高于 15% 时才能开启";
        else sum = "充电器直接为平板供电，电池不充不放，适合边充边玩";
        itemBypass.summary(sum);
    }

    private String statusLine(BatteryState s) {
        String st = s.status == null ? "" : s.status;
        switch (st) {
            case "Charging": {
                String t = s.timeToFullS > 0 ? " · 约 " + duration(s.timeToFullS) + "后充满" : "";
                if (s.limitOn()) t = " · 充到 " + s.limit + "% 停止";
                return "正在充电" + t;
            }
            case "Full":
                return "已充满电";
            case "Not charging":
                if (s.bypassOn) return "旁路供电中 · 电池不充不放";
                if (s.limitOn() && s.level != BatteryState.NA && s.level >= s.rechargeLevel()) return "已达到充电上限，暂停充电";
                if (s.protectOn) return "长期插电保护中，暂停充电";
                if (s.level != BatteryState.NA && s.level >= 100) return "已充满电";
                return "已连接电源，未在充电";
            case "Discharging":
                return s.timeToEmptyS > 0 ? "未在充电 · 预计还能使用 " + duration(s.timeToEmptyS) : "未在充电";
            default:
                return s.pluggedIn() ? "已连接电源" : st.isEmpty() ? "未在充电" : st;
        }
    }

    private void saveSummary(BatteryState s) {
        if (!(s.infoOk || s.limitOk)) return;
        StringBuilder b = new StringBuilder();
        if (s.soh != BatteryState.NA) b.append("健康度 ").append(s.soh).append('%');
        if (s.bypassOn) b.append(b.length() > 0 ? " · " : "").append("旁路充电已开启");
        else if (s.limitOk && s.limitOn()) b.append(b.length() > 0 ? " · " : "").append("充电上限 ").append(s.limit).append('%');
        else if (s.protectOk && s.protectOn) b.append(b.length() > 0 ? " · " : "").append("长期插电保护已开启");
        if (b.length() > 0) prefs.edit().putString(KEY_SUMMARY, b.toString()).apply();
    }

    // ------------------------------------------------------------------ actions

    private interface Done {
        void run(Resp r);
    }

    /** Runs a write command, keeps the row frozen meanwhile, then refreshes everything. */
    private void write(PrefItem item, String cmd, Done after) {
        if (item != null) item.setBusy(true);
        exec.execute(() -> {
            Resp r = backend.exec(cmd, Backend.WRITE_TIMEOUT_MS);
            ui.post(() -> {
                if (isDestroyed()) return;
                if (item != null) item.setBusy(false);
                if (!r.ok()) {
                    if (state != null) bind(state); // put the switch back right away
                    showError(r.errorText());
                }
                if (after != null) after.run(r);
                refreshOnce(null);
            });
        });
    }

    private void showError(String msg) {
        new M3Dialog(this, pal).title("操作失败").message(msg).button("确定", null).show();
    }

    private int lastLimit() {
        return prefs.getInt(KEY_LAST_LIMIT, 80);
    }

    private int lastRecharge() {
        return prefs.getInt(KEY_LAST_RECHARGE, state != null ? state.recharge : 95);
    }

    private void toggleLimit(PrefItem item, boolean on) {
        item.setChecked(on, true);
        if (on) {
            int l = lastLimit(), rc = lastRecharge();
            item.summary("正在设置…");
            write(item, "battery limit " + l + " " + rc, null);
        } else {
            if (state != null && state.limitOn()) prefs.edit().putInt(KEY_LAST_LIMIT, state.limit).putInt(KEY_LAST_RECHARGE, state.recharge).apply();
            item.summary("正在关闭…");
            write(item, "battery limit off", null);
        }
    }

    private void toggleProtect(PrefItem item, boolean on) {
        item.setChecked(on, true);
        if (on) {
            int mn = state != null ? state.protMin : 75, mx = state != null ? state.protMax : 80;
            item.summary("正在开启…");
            write(item, "battery protect on " + mn + " " + mx, null);
        } else {
            item.summary("正在关闭…");
            write(item, "battery protect off", null);
        }
    }

    private void toggleBypass(PrefItem item, boolean on) {
        if (!on) {
            item.setChecked(false, true);
            item.summary("正在关闭…");
            write(item, "battery bypass off", null);
            return;
        }
        new M3Dialog(this, pal)
                .title("开启旁路充电？")
                .message("开启后，接着充电器时由充电器直接给平板供电，电池既不充电也不放电。\n\n"
                        + "开启需要几秒钟验证。")
                .button("取消", null)
                .button("开启", () -> {
                    item.setChecked(true, true);
                    item.summary("正在开启…（需要几秒钟验证）");
                    write(item, "battery bypass on", null);
                    return true;
                })
                .show();
    }

    // ------------------------------------------------------------------ dialogs

    /** A labelled slider row: title, value on the right, and a SeekBar stepping by 5. */
    private final class Slider {
        final LinearLayout view;
        final TextView valueText;
        final SeekBar bar;
        final int min, step;
        Runnable onChange;

        Slider(String label, int min, int max, int step, int value) {
            this.min = min;
            this.step = step;
            Context c = MainActivity.this;
            view = new LinearLayout(c);
            view.setOrientation(LinearLayout.VERTICAL);
            LinearLayout head = new LinearLayout(c);
            TextView l = Ui.titleMedium(c, pal);
            l.setText(label);
            head.addView(l, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
            valueText = Ui.text(c, 16, 24, "variable-title-medium", 500, pal.primary);
            head.addView(valueText);
            view.addView(head, matchWrap());
            bar = new SeekBar(c);
            bar.setMax((max - min) / step);
            bar.setProgress(Math.max(0, Math.min(bar.getMax(), (value - min) / step)));
            bar.setProgressTintList(ColorStateList.valueOf(pal.primary));
            bar.setThumbTintList(ColorStateList.valueOf(pal.primary));
            bar.setProgressBackgroundTintList(ColorStateList.valueOf(pal.outlineVariant));
            bar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
                @Override
                public void onProgressChanged(SeekBar s, int p, boolean user) {
                    update();
                }

                @Override
                public void onStartTrackingTouch(SeekBar s) {
                }

                @Override
                public void onStopTrackingTouch(SeekBar s) {
                }
            });
            LinearLayout.LayoutParams bl = matchWrap();
            bl.topMargin = Ui.dp(c, 8);
            view.addView(bar, bl);
            update();
        }

        int value() {
            return min + bar.getProgress() * step;
        }

        void update() {
            valueText.setText(value() + "%");
            if (onChange != null) onChange.run();
        }
    }

    private LinearLayout dialogBody() {
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPaddingRelative(0, Ui.dp(this, 8), 0, 0);
        return body;
    }

    private void showLimitDialog() {
        if (state == null || !state.limitOk) return;
        int cur = state.limitOn() ? state.limit : lastLimit();
        int rc = state.limitOn() ? state.recharge : lastRecharge();
        LinearLayout body = dialogBody();
        Slider limit = new Slider("充电上限", 50, 100, 5, cur);
        Slider recharge = new Slider("恢复充电比例", 50, 100, 5, rc);
        TextView hint = Ui.bodyMedium(this, pal);
        Runnable upd = () -> hint.setText(limit.value() >= 100
                ? "充电上限为 100% 相当于关闭此功能。"
                : "电量到 " + limit.value() + "% 时停止充电，降到 " + (limit.value() * recharge.value() / 100) + "% 以下时重新开始充电。");
        limit.onChange = upd;
        recharge.onChange = upd;
        body.addView(limit.view, matchWrap());
        LinearLayout.LayoutParams rl = matchWrap();
        rl.topMargin = Ui.dp(this, 20);
        body.addView(recharge.view, rl);
        LinearLayout.LayoutParams hl = matchWrap();
        hl.topMargin = Ui.dp(this, 16);
        body.addView(hint, hl);
        upd.run();
        new M3Dialog(this, pal)
                .title("充电上限")
                .view(body)
                .button("取消", null)
                .button("确定", () -> {
                    int l = limit.value(), r = recharge.value();
                    if (l >= 100) {
                        itemLimit.setChecked(false, true);
                        write(itemLimit, "battery limit off", null);
                    } else {
                        prefs.edit().putInt(KEY_LAST_LIMIT, l).putInt(KEY_LAST_RECHARGE, r).apply();
                        itemLimit.setChecked(true, true);
                        itemLimit.summary("正在设置…");
                        write(itemLimit, "battery limit " + l + " " + r, null);
                    }
                    return true;
                })
                .show();
    }

    private void showProtectDialog() {
        if (state == null || !state.protectOk) return;
        LinearLayout body = dialogBody();
        Slider max = new Slider("上限", 25, 100, 5, state.protMax);
        Slider min = new Slider("下限", 20, 95, 5, state.protMin);
        TextView hint = Ui.bodyMedium(this, pal);
        Runnable upd = () -> {
            boolean bad = min.value() >= max.value();
            hint.setTextColor(bad ? pal.error : pal.onSurfaceVariant);
            hint.setText(bad ? "下限要低于上限。"
                    : "插着电时，电量高于 " + max.value() + "% 停止充电，低于 " + min.value() + "% 时重新充电。");
        };
        max.onChange = upd;
        min.onChange = upd;
        body.addView(max.view, matchWrap());
        LinearLayout.LayoutParams ml = matchWrap();
        ml.topMargin = Ui.dp(this, 20);
        body.addView(min.view, ml);
        LinearLayout.LayoutParams hl = matchWrap();
        hl.topMargin = Ui.dp(this, 16);
        body.addView(hint, hl);
        upd.run();
        new M3Dialog(this, pal)
                .title("长期插电保护")
                .view(body)
                .button("取消", null)
                .button(state.protectOn ? "确定" : "开启", () -> {
                    int mn = min.value(), mx = max.value();
                    if (mn >= mx) return false;   // keep the dialog open; the hint already says why
                    itemProtect.setChecked(true, true);
                    itemProtect.summary("正在设置…");
                    write(itemProtect, "battery protect on " + mn + " " + mx, null);
                    return true;
                })
                .show();
    }

    // ------------------------------------------------------------------ formatting

    static String fmtDeci(int deci) {
        return (deci < 0 ? "-" : "") + Math.abs(deci) / 10 + "." + Math.abs(deci) % 10;
    }

    static String fmtMa(int ma) {
        return String.format(Locale.ROOT, "%s%,d mA", ma > 0 ? "+" : "", ma);
    }

    static String mah(long uah) {
        return String.format(Locale.ROOT, "%,d mAh", uah / 1000);
    }

    static String duration(long s) {
        long m = Math.max(1, Math.round(s / 60.0));
        if (m < 60) return m + " 分钟";
        return (m / 60) + " 小时" + (m % 60 == 0 ? "" : " " + (m % 60) + " 分钟");
    }

    static String healthName(String h) {
        if (h == null) return "—";
        switch (h) {
            case "Good": return "良好";
            case "Overheat": return "过热";
            case "Cold": return "过冷";
            case "Dead": return "损坏";
            case "Over voltage": return "电压过高";
            case "Unspecified failure": return "故障";
            case "Warm": return "偏热";
            case "Cool": return "偏冷";
            case "Hot": return "过热";
            case "Unknown": return "未知";
            default: return h;
        }
    }
}
