package com.lenovo.tb321fu.attest;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.ColorStateList;
import android.content.res.Configuration;
import android.graphics.Insets;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Base64;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.text.DateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * 机型伪装与密钥认证: global build-identity spoofing (pick a Pixel from keymint's catalog), the
 * installed Keybox (type, revocation, certificate chains, replace), and on-device RKP issuance.
 * Opened from Settings > About tablet, right below "Model". Everything goes through the herald
 * broker's herald-apps channel; the allowlist is files/com.lenovo.tb321fu.attest.allow.
 *
 * Output formats (keymint --webui-*, see herald-core/engine): success = one compact JSON line
 * (or a bare word for revocation / import), failure = "err <cmd> rc=N" then keymint's stderr.
 */
public final class MainActivity extends Activity {
    static final String PREFS = "attest";
    static final String KEY_SUMMARY = "tile_summary";
    private static final int REQ_KEYBOX = 1;
    /** keymint takes the keybox as one base64 argument chunk of at most 49152 chars = 36864 bytes. */
    private static final int KEYBOX_MAX = 36864;

    private static final long T_READ = 8_000, T_LIST = 110_000, T_SPOOF = 150_000, T_REVOKE = 25_000,
            T_RKP = 120_000, T_WRITE = 25_000;

    private final Handler ui = new Handler(Looper.getMainLooper());
    private final ExecutorService exec = Executors.newSingleThreadExecutor();
    private HeraldBackend backend;
    private Pal pal;
    private SharedPreferences prefs;

    private PrefGroup errGroup;
    private PrefItem errItem;
    private View spoofSection, keyboxSection, rkpSection, footer;
    private PrefItem itemSpoof, itemModel;
    private PrefItem itemKbType, itemKbStatus, itemKbChain, itemKbReplace;
    private PrefGroup rkpGroup;
    private PrefItem itemRkpIssue;
    private final List<PrefItem> rkpItems = new ArrayList<>();

    // last known state
    private boolean spoofOn;
    private String spoofModel;
    private boolean kbValid;
    private String kbSummary;
    private Resp lastGet, lastKb, lastRkp;
    private String lastRevocation;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        backend = new HeraldBackend(getApplicationContext());
        prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        build();
    }

    @Override
    public void onConfigurationChanged(Configuration c) {
        super.onConfigurationChanged(c);
        build();
        rebind();
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

    // ------------------------------------------------------------------ layout

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

        ScrollView scroll = new ScrollView(c);
        scroll.setClipToPadding(false);
        LinearLayout content = new LinearLayout(c);
        content.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(content, new ScrollView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        root.addView(scroll, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        errGroup = new PrefGroup(c);
        errItem = new PrefItem(c, pal, "无法连接系统认证服务");
        errGroup.addItem(errItem);
        errGroup.updateShapes();
        errGroup.setVisibility(View.GONE);
        LinearLayout.LayoutParams el = matchWrap();
        el.topMargin = Ui.dp(c, 16);
        content.addView(errGroup, el);

        // 机型伪装
        PrefGroup sg = new PrefGroup(c);
        itemSpoof = new PrefItem(c, pal, "全局机型伪装").withSwitch(PrefItem.SWITCH, (item, on) -> toggleSpoof(on));
        itemModel = new PrefItem(c, pal, "伪装机型");
        itemModel.setOnClickListener(v -> pickModel());
        sg.addItem(itemSpoof);
        sg.addItem(itemModel);
        sg.updateShapes();
        spoofSection = section(content, "机型伪装", sg);

        // Keybox
        PrefGroup kg = new PrefGroup(c);
        itemKbType = new PrefItem(c, pal, "Keybox");
        itemKbStatus = new PrefItem(c, pal, "证书状态");
        itemKbChain = new PrefItem(c, pal, "证书链");
        itemKbChain.summary("查看 RSA / EC 证书链");
        itemKbChain.setOnClickListener(v -> showChain());
        itemKbReplace = new PrefItem(c, pal, "更换 Keybox");
        itemKbReplace.summary("从文件导入 keybox.xml");
        itemKbReplace.setOnClickListener(v -> confirmReplaceKeybox());
        kg.addItem(itemKbType);
        kg.addItem(itemKbStatus);
        kg.addItem(itemKbChain);
        kg.addItem(itemKbReplace);
        kg.updateShapes();
        keyboxSection = section(content, "Keybox", kg);

        // 本机 RKP 签发
        rkpGroup = new PrefGroup(c);
        itemRkpIssue = new PrefItem(c, pal, "签发证书");
        itemRkpIssue.summary("向 Google 申请一套本机的远程密钥证书");
        itemRkpIssue.setOnClickListener(v -> confirmIssue());
        rkpGroup.addItem(itemRkpIssue);
        rkpGroup.updateShapes();
        rkpItems.clear();
        rkpSection = section(content, "本机 RKP 签发", rkpGroup);

        footer = buildFooter();
        content.addView(footer, matchWrap());
        for (View v : new View[]{spoofSection, keyboxSection, rkpSection, footer}) v.setVisibility(View.GONE);

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
        t.setText("全局机型伪装：把系统和密钥认证里的机型信息换成所选的 Pixel 设备，安全补丁日期跟着同步。改动重启后生效。\n"
                + "Keybox：系统用它为应用的密钥签发认证证书。更换后，用旧 Keybox 生成的应用密钥可能无法再用。\n"
                + "本机 RKP 签发：在本机生成密钥，把公钥和设备信息发给 Google 换取证书，结果先暂存，导入后才替换当前 Keybox。"
                + "只有部分设备支持，Google 可能拒绝；不保证通过 Play Integrity。");
        t.setMaxLines(Integer.MAX_VALUE);
        LinearLayout.LayoutParams tl = matchWrap();
        tl.topMargin = Ui.dp(c, 16);
        f.addView(t, tl);
        return f;
    }

    // ------------------------------------------------------------------ helpers

    /** keymint output when it succeeded (first line is not "err ..."), else null. */
    static String okText(Resp r) {
        if (r.unavailable || r.timeout) return null;
        String f = r.first();
        return f.isEmpty() || f.startsWith("err") ? null : f;
    }

    static JSONObject okJson(Resp r) {
        String t = okText(r);
        if (t == null || !t.startsWith("{")) return null;
        try {
            return new JSONObject(t);
        } catch (Exception e) {
            return null;
        }
    }

    /** Error text for a failed call: everything after the "err ..." line (keymint's own message), or the line. */
    static String errText(Resp r) {
        if (r.unavailable) return "系统认证服务未响应";
        if (r.timeout) return "系统认证服务响应超时";
        List<String> l = r.lines();
        if (l.size() > 1) return String.join("\n", l.subList(1, l.size()));
        return r.errorText();
    }

    private void fail(String title, Resp r) {
        new M3Dialog(this, pal).title(title).message(errText(r)).button("确定", null).show();
    }

    private void info(String title, String msg) {
        new M3Dialog(this, pal).title(title).message(msg).button("确定", null).show();
    }

    private interface Job {
        Resp run();
    }

    private interface Then {
        void done(Resp r);
    }

    private void async(Job job, Then then) {
        exec.execute(() -> {
            Resp r = job.run();
            ui.post(() -> {
                if (!isDestroyed()) then.done(r);
            });
        });
    }

    /** A modal "working…" dialog for long actions (network). */
    private M3Dialog busy(String title, String msg) {
        M3Dialog d = new M3Dialog(this, pal).title(title).message(msg).modal();
        d.show();
        return d;
    }

    // ------------------------------------------------------------------ data

    private void refresh() {
        async(() -> backend.exec("get", T_READ), r -> {
            lastGet = r;
            bindSpoof();
            async(() -> backend.exec("keybox_state", T_READ), k -> {
                lastKb = k;
                lastRevocation = null;
                bindKeybox();
                async(() -> backend.exec("rkp_list", T_READ), l -> {
                    lastRkp = l;
                    bindRkp();
                    if (kbValid) {
                        async(() -> backend.exec("keybox_revocation", T_REVOKE), rv -> {
                            String t = okText(rv);
                            lastRevocation = t == null ? "?" : t;
                            bindKeybox();
                        });
                    }
                });
            });
        });
    }

    private void rebind() {
        if (lastGet != null) bindSpoof();
        if (lastKb != null) bindKeybox();
        if (lastRkp != null) bindRkp();
    }

    private void bindSpoof() {
        Resp r = lastGet;
        boolean reachable = !r.unavailable && !r.timeout;
        Ui.setVisible(errGroup, !reachable);
        if (!reachable) {
            errItem.summary(r.unavailable
                    ? "这个页面需要系统里的认证服务支持。请确认系统已更新到包含它的版本。"
                    : "系统认证服务响应超时，稍后再试。");
        }
        for (View v : new View[]{spoofSection, keyboxSection, rkpSection, footer}) Ui.setVisible(v, reachable);
        if (!reachable) return;
        JSONObject j = okJson(r);
        spoofOn = "on".equals(r.kv("HERALD_GLOBAL_PIF_FLAG"));
        spoofModel = null;
        String patch = null, fp = null;
        if (j != null && j.optBoolean("enabled", j.has("fingerprint"))) {
            spoofModel = j.optString("model", null);
            patch = j.optString("security_patch", null);
            fp = j.optString("fingerprint", null);
        }
        if (!itemSpoof.isBusy()) {
            itemSpoof.setChecked(spoofOn, true);
            itemSpoof.summary(spoofOn
                    ? "开启 · " + (spoofModel == null ? "" : spoofModel) + (patch == null ? "" : " · 安全补丁 " + patch)
                    : "关闭 · 使用本机真实身份");
        }
        itemModel.value(spoofModel == null ? "未选择" : spoofModel);
        itemModel.summary(fp != null ? fp : j == null ? "读取失败：" + errText(r) : "点按从 Pixel 机型目录里选择（需要联网）");
        saveSummary();
    }

    private void bindKeybox() {
        JSONObject j = okJson(lastKb);
        if (j == null) {
            kbValid = false;
            itemKbType.value("—");
            itemKbType.summary("读取失败：" + errText(lastKb));
            itemKbStatus.value("—");
            itemKbStatus.summary(null);
        } else {
            kbValid = j.optBoolean("valid");
            boolean bundled = j.optBoolean("bundled");
            String type;
            if (!kbValid) type = "无效";
            else if (bundled) type = "内置";
            else switch (j.optString("source")) {
                case "google_hardware": type = "Google 硬件根证书"; break;
                case "google_remote": type = "Google 远程密钥配置（RKP）"; break;
                default: type = "未知来源"; break;
            }
            String level;
            switch (j.optString("level")) {
                case "tee": level = "TEE"; break;
                case "strongbox": level = "StrongBox"; break;
                default: level = "未知"; break;
            }
            itemKbType.value(type);
            itemKbType.summary("安全级别 " + level + (kbValid && !bundled ? " · 自定义 Keybox" : ""));
            kbSummary = kbValid ? "Keybox 有效" : "Keybox 无效";
            String st, sum = null;
            if (!kbValid) {
                st = "本地校验失败";
            } else if (lastRevocation == null) {
                st = "检查中…";
            } else {
                switch (lastRevocation) {
                    case "not_listed": st = "未吊销"; break;
                    case "suspended": st = "已吊销"; sum = "Google 已暂停这份证书（suspended）"; break;
                    case "revoked": st = "已吊销"; sum = "Google 已吊销这份证书（revoked）"; break;
                    case "not_checked": st = "未检查"; break;
                    default: st = "检查失败"; sum = "需要联网查询 Google 的证书状态列表"; break;
                }
                if (st.equals("已吊销")) kbSummary = "Keybox 已吊销";
            }
            itemKbStatus.value(st);
            itemKbStatus.summary(sum);
        }
        saveSummary();
    }

    private void bindRkp() {
        for (PrefItem p : rkpItems) rkpGroup.removeView(p);
        rkpItems.clear();
        JSONObject j = okJson(lastRkp);
        JSONArray a = j == null ? null : j.optJSONArray("artifacts");
        if (a != null) {
            DateFormat df = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT);
            for (int i = 0; i < a.length(); i++) {
                JSONObject o = a.optJSONObject(i);
                if (o == null) continue;
                String id = o.optString("id");
                long t = o.optLong("created_at");
                String when = df.format(new Date(t * 1000));
                String subjects = joinSubjects(o.optJSONArray("chain_subjects"));
                PrefItem p = new PrefItem(this, pal, "暂存结果 · " + when);
                p.summary(subjects);
                p.value("导入");
                p.setOnClickListener(v -> confirmImport(id, when, subjects));
                rkpGroup.addItem(p);
                rkpItems.add(p);
            }
        }
        itemRkpIssue.summary(j == null && lastRkp != null && okText(lastRkp) == null
                ? "暂存结果读取失败：" + errText(lastRkp)
                : rkpItems.isEmpty() ? "向 Google 申请一套本机的远程密钥证书" : "暂存了 " + rkpItems.size() + " 个结果，导入后才会替换当前 Keybox");
        rkpGroup.updateShapes();
    }

    static String joinSubjects(JSONArray s) {
        if (s == null) return "";
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            if (i > 0) b.append(" · ");
            b.append(s.optString(i));
        }
        return b.toString();
    }

    private void saveSummary() {
        StringBuilder b = new StringBuilder();
        if (lastGet != null && okText(lastGet) != null) b.append(spoofOn && spoofModel != null ? "伪装为 " + spoofModel : "未伪装");
        if (kbSummary != null) b.append(b.length() > 0 ? " · " : "").append(kbSummary);
        if (b.length() > 0) prefs.edit().putString(KEY_SUMMARY, b.toString()).apply();
    }

    // ------------------------------------------------------------------ 机型伪装

    private void toggleSpoof(boolean on) {
        if (on) {
            itemSpoof.setChecked(false, true);   // stays off until a model is chosen and applied
            pickModel();
            return;
        }
        itemSpoof.setChecked(true, true);
        new M3Dialog(this, pal)
                .title("关闭全局机型伪装？")
                .message("恢复使用本机真实身份，安全补丁日期同步回本机的值。重启后生效。")
                .button("取消", null)
                .button("关闭", () -> {
                    itemSpoof.setBusy(true);
                    itemSpoof.summary("正在关闭…");
                    async(() -> backend.exec("disable", T_WRITE), r -> {
                        itemSpoof.setBusy(false);
                        if (okText(r) == null) fail("关闭失败", r);
                        else info("已关闭", "重启平板后恢复本机真实身份。");
                        refresh();
                    });
                    return true;
                })
                .show();
    }

    private void pickModel() {
        M3Dialog wait = busy("正在读取机型目录", "需要联网，最多约半分钟…");
        async(() -> backend.exec("list", T_LIST), r -> {
            wait.dismiss();
            String t = okText(r);
            JSONArray a = null;
            try {
                if (t != null && t.startsWith("[")) a = new JSONArray(t);
            } catch (Exception ignored) {
                a = null;
            }
            if (a == null || a.length() == 0) {
                fail("读取机型目录失败", r);
                return;
            }
            LinearLayout list = new LinearLayout(this);
            list.setOrientation(LinearLayout.VERTICAL);
            PrefGroup g = new PrefGroup(this);
            M3Dialog d = new M3Dialog(this, pal).title("选择伪装机型");
            for (int i = 0; i < a.length(); i++) {
                JSONObject o = a.optJSONObject(i);
                if (o == null) continue;
                String model = o.optString("model"), product = o.optString("product");
                PrefItem p = new PrefItem(this, pal, model);
                p.summary(product);
                p.setOnClickListener(v -> {
                    d.dismiss();
                    confirmSpoof(model, product);
                });
                g.addItem(p);
            }
            g.updateShapes();
            list.addView(g, matchWrap());
            d.view(list).button("取消", null).show();
        });
    }

    private void confirmSpoof(String model, String product) {
        new M3Dialog(this, pal)
                .title("伪装为 " + model + "？")
                .message("会联网下载这台设备的系统信息，写入后打开全局机型伪装，安全补丁日期同步为它的日期。"
                        + "Google Play 服务和 Play 商店会被重启。重启平板后完全生效。")
                .button("取消", null)
                .button("伪装", () -> {
                    M3Dialog wait = busy("正在设置", "正在下载 " + model + " 的系统信息，最多约一分钟…");
                    async(() -> backend.exec("spoof_on " + product, T_SPOOF), r -> {
                        wait.dismiss();
                        String t = okText(r);
                        if (t == null) {
                            fail("设置失败", r);
                        } else if (t.contains("WILL_FALLBACK")) {
                            info("已保存，但会回落", "这个机型的信息不完整，重启后会回落到默认机型 "
                                    + (r.kv("fallback_model") == null ? "" : r.kv("fallback_model")) + "。");
                        } else {
                            info("已设置", "伪装为 " + model + "。重启平板后生效。");
                        }
                        refresh();
                    });
                    return true;
                })
                .show();
    }

    // ------------------------------------------------------------------ Keybox

    private void showChain() {
        M3Dialog wait = busy("正在读取证书链", "请稍候…");
        async(() -> backend.exec("keybox_inspector", T_READ), r -> {
            wait.dismiss();
            JSONObject j = okJson(r);
            if (j == null) {
                fail("读取证书链失败", r);
                return;
            }
            StringBuilder b = new StringBuilder();
            for (String alg : new String[]{"rsa", "ec"}) {
                JSONObject c = j.optJSONObject(alg);
                b.append(alg.toUpperCase()).append(" 证书链：");
                if (c == null) {
                    b.append("无\n\n");
                    continue;
                }
                b.append(c.optInt("chain_length")).append(" 张\n");
                JSONArray certs = c.optJSONArray("certificates");
                for (int i = 0; certs != null && i < certs.length(); i++) {
                    JSONObject x = certs.optJSONObject(i);
                    if (x == null) continue;
                    b.append(i == 0 ? "· 叶证书" : "· 第 " + (i + 1) + " 张").append('\n')
                            .append("  主题：").append(x.optString("subject")).append('\n')
                            .append("  颁发者：").append(x.optString("issuer")).append('\n')
                            .append("  序列号：").append(x.optString("serial")).append('\n')
                            .append("  有效期：").append(x.optString("valid_from")).append(" 至 ").append(x.optString("valid_until")).append('\n');
                }
                b.append('\n');
            }
            info("证书链", b.toString().trim());
        });
    }

    private void confirmReplaceKeybox() {
        new M3Dialog(this, pal)
                .title("更换 Keybox？")
                .message("会替换当前使用的 Keybox。用旧 Keybox 生成的应用密钥可能无法再用，相关应用可能需要重新登录或重新绑定。\n\n"
                        + "接下来选择 keybox.xml 文件（不超过 36 KB）。")
                .button("取消", null)
                .button("选择文件", () -> {
                    Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
                    i.addCategory(Intent.CATEGORY_OPENABLE);
                    i.setType("*/*");
                    i.putExtra(Intent.EXTRA_MIME_TYPES, new String[]{"text/xml", "application/xml", "text/plain", "application/octet-stream"});
                    startActivityForResult(i, REQ_KEYBOX);
                    return true;
                })
                .show();
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQ_KEYBOX || resultCode != RESULT_OK || data == null || data.getData() == null) return;
        Uri uri = data.getData();
        byte[] xml;
        try (InputStream in = getContentResolver().openInputStream(uri)) {
            if (in == null) throw new java.io.IOException("打不开文件");
            ByteArrayOutputStream o = new ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) {
                o.write(buf, 0, n);
                if (o.size() > KEYBOX_MAX) break;
            }
            xml = o.toByteArray();
        } catch (Exception e) {
            info("读取文件失败", String.valueOf(e.getMessage()));
            return;
        }
        if (xml.length > KEYBOX_MAX) {
            info("文件太大", "Keybox 文件不能超过 36 KB。");
            return;
        }
        String head = new String(xml, 0, Math.min(xml.length, 4096), StandardCharsets.UTF_8);
        if (!head.contains("<AndroidAttestation") && !head.contains("<Keybox")) {
            info("不是 Keybox 文件", "所选文件里没有 AndroidAttestation / Keybox 内容。");
            return;
        }
        String b64 = Base64.encodeToString(xml, Base64.NO_WRAP);
        M3Dialog wait = busy("正在更换 Keybox", "请稍候…");
        async(() -> {
            try (FileOutputStream o = new FileOutputStream(new File(getFilesDir(), "herald_keybox_b64_in"))) {
                o.write(b64.getBytes(StandardCharsets.US_ASCII));
            } catch (Exception e) {
                return Resp.error("keybox_import", "写临时文件失败：" + e.getMessage());
            }
            return backend.exec("keybox_import", T_WRITE);
        }, r -> {
            wait.dismiss();
            new File(getFilesDir(), "herald_keybox_b64_in").delete();
            if (!"ok".equals(okText(r))) fail("更换失败", r);
            else info("已更换", "Keybox 已更换，会自动重新加载。");
            refresh();
        });
    }

    // ------------------------------------------------------------------ RKP

    private void confirmIssue() {
        new M3Dialog(this, pal)
                .title("签发本机 RKP 证书？")
                .message("会在本机生成一把 P-256 私钥，把公钥、系统指纹和设备的 RKP 凭证发给 Google 申请证书；私钥不会上传。\n\n"
                        + "只有部分设备支持，Google 可能拒绝。签发不能修复 TEE 或指纹支付，也不保证通过 Play Integrity。"
                        + "结果先暂存，不会替换当前 Keybox。\n\n"
                        + "如果提示结果不确定，不要反复重试。")
                .button("取消", null)
                .button("我已了解，签发一次", () -> {
                    M3Dialog wait = busy("正在签发", "正在和 Google 通信，最多约一分钟。请不要离开这个页面，也不要再次签发。");
                    async(() -> backend.exec("rkp_issue v2", T_RKP), r -> {
                        wait.dismiss();
                        JSONObject j = okJson(r);
                        if (j == null) fail("签发失败", r);
                        else info("已签发", "结果已暂存（" + joinSubjects(j.optJSONArray("chain_subjects")) + "）。导入后才会替换当前 Keybox。");
                        refresh();
                    });
                    return true;
                })
                .show();
    }

    private void confirmImport(String id, String when, String subjects) {
        new M3Dialog(this, pal)
                .title("用这个结果替换 Keybox？")
                .message(when + "\n" + subjects + "\n\n"
                        + "会替换当前使用的 Keybox。用旧 Keybox 生成的应用密钥可能无法再用。导入前会重新校验证书链。")
                .button("取消", null)
                .button("替换 Keybox", () -> {
                    M3Dialog wait = busy("正在导入", "请稍候…");
                    async(() -> backend.exec("rkp_import " + id, T_WRITE), r -> {
                        wait.dismiss();
                        if (!"rkp_imported".equals(okText(r))) fail("导入失败", r);
                        else info("已导入", "Keybox 已替换为本机 RKP 签发的证书。");
                        refresh();
                    });
                    return true;
                })
                .show();
    }
}
