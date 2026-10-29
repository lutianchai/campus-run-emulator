package com.dsh.space;

import android.app.Activity;
import android.app.AlertDialog;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 运动世界校园 · 账号空间切换器
 *
 * 每个「空间」= 一个 Android 用户(user)，运动世界的登录态/数据完全隔离。
 * 本应用通过本机 adbd（127.0.0.1:5555，本模拟器 ro.adb.secure=0）执行特权命令，
 * 因此既是普通 APK，又能做 am switch-user / pm create-user 这类系统级操作。
 */
public class MainActivity extends Activity {

    static final String PKG = "com.zjwh.android_wh_physicalfitness";
    static final String CLS = ".mvi.splash.SplashActivity";
    static final String COMP = PKG + "/" + CLS;
    static final String SELF = "com.dsh.space";

    static final int BG = 0xFFF2F3F6;
    static final int CARD = 0xFFFFFFFF;
    static final int PRIMARY = 0xFF2F6BFF;
    static final int PRIMARY_SOFT = 0xFFE7EDFF;
    static final int TEXT = 0xFF111827;
    static final int SUB = 0xFF6B7280;
    static final int OK = 0xFF12A150;
    static final int WARN = 0xFFDC6803;
    static final int DANGER = 0xFFD92D20;

    final Handler ui = new Handler(Looper.getMainLooper());
    final List<Space> spaces = new ArrayList<>();

    LinearLayout listBox;
    TextView headStatus;
    TextView logView;
    Button btnNew, btnLaunch;
    int currentUid = -1;
    volatile boolean busy = false;

    static class Space {
        int id;
        String name;
        boolean running;
        boolean hasApp;
        boolean isCurrent;
    }

    // ---------------- adb 通道 ----------------

    private AdbClient adb;
    private boolean adbOk = false;

    private synchronized String run(String cmd) {
        try {
            if (adb == null || !adbOk) {
                adb = new AdbClient();
                adb.connect();
                adbOk = true;
            }
            String out = adb.shell(cmd);
            if (out.startsWith("[adb ")) {
                adbOk = false;
            }
            return out;
        } catch (Exception e) {
            adbOk = false;
            return "[adb 连接失败: " + e.getMessage() + "]";
        }
    }

    /** 用独立连接跑长命令：执行期间保持通道打开，adbd 就不会把子进程带走 */
    private String runLong(String cmd, int timeoutMs) {
        AdbClient c = new AdbClient();
        try {
            c.connect();
            c.setTimeout(timeoutMs);
            return c.shell(cmd);
        } catch (Exception e) {
            return "[adb 连接失败: " + e.getMessage() + "]";
        } finally {
            c.close();
        }
    }

    // ---------------- 生命周期 ----------------

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        setContentView(buildUi());
        refresh();
    }

    @Override
    protected void onResume() {
        super.onResume();
        refresh();
    }

    // ---------------- UI ----------------

    private int dp(int v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics());
    }

    private GradientDrawable card(int color, int radiusDp) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(color);
        g.setCornerRadius(dp(radiusDp));
        return g;
    }

    private Button pill(String text, boolean filled) {
        Button b = new Button(this);
        b.setText(text);
        b.setAllCaps(false);
        b.setTextSize(14);
        b.setTextColor(filled ? Color.WHITE : PRIMARY);
        b.setBackground(filled ? card(PRIMARY, 11) : card(PRIMARY_SOFT, 11));
        b.setPadding(dp(8), dp(4), dp(8), dp(4));
        b.setMinHeight(dp(40));
        b.setStateListAnimator(null);
        return b;
    }

    private View buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(BG);
        root.setPadding(dp(16), dp(18), dp(16), dp(10));

        TextView title = new TextView(this);
        title.setText("运动世界 · 账号空间");
        title.setTextSize(22);
        title.setTextColor(TEXT);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setOnLongClickListener(v -> {
            diag();
            return true;
        });
        root.addView(title);

        headStatus = new TextView(this);
        headStatus.setTextSize(13);
        headStatus.setTextColor(SUB);
        headStatus.setPadding(0, dp(6), 0, dp(12));
        root.addView(headStatus);

        ScrollView sv = new ScrollView(this);
        sv.setLayoutParams(new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        sv.setClipToPadding(false);
        listBox = new LinearLayout(this);
        listBox.setOrientation(LinearLayout.VERTICAL);
        sv.addView(listBox);
        root.addView(sv);

        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setPadding(0, dp(8), 0, dp(8));
        Button btnRefresh = pill("刷新", false);
        btnNew = pill("新建空间", false);
        btnLaunch = pill("启动运动世界", true);
        LinearLayout.LayoutParams lp1 = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        lp1.rightMargin = dp(8);
        LinearLayout.LayoutParams lp2 = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.25f);
        lp2.rightMargin = dp(8);
        bar.addView(btnRefresh, lp1);
        bar.addView(btnNew, lp2);
        bar.addView(btnLaunch, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.6f));
        root.addView(bar);

        logView = new TextView(this);
        logView.setTextSize(11);
        logView.setTextColor(0xFF4B5563);
        logView.setBackground(card(0xFFE7EAF0, 10));
        logView.setPadding(dp(10), dp(7), dp(10), dp(7));
        logView.setMaxLines(4);
        logView.setText("就绪 · 长按卡片可删除空间");
        root.addView(logView);

        btnRefresh.setOnClickListener(v -> refresh());
        btnNew.setOnClickListener(v -> askNewSpace());
        btnLaunch.setOnClickListener(v -> {
            if (currentUid >= 0) launchHere();
        });
        return root;
    }

    private void log(String s) {
        final String line = new SimpleDateFormat("HH:mm:ss", Locale.US).format(new Date()) + "  " + s;
        ui.post(() -> {
            String old = logView.getText().toString();
            logView.setText(line + (old.isEmpty() ? "" : "\n" + old));
        });
    }

    // ---------------- 数据 ----------------

    void refresh() {
        new Thread(() -> {
            List<Space> found = new ArrayList<>();
            String users = run("pm list users");
            String cur = run("am get-current-user").trim();
            int curId = -1;
            try {
                curId = Integer.parseInt(cur.replaceAll("[^0-9]", ""));
            } catch (Exception ignored) {
            }
            Matcher m = Pattern.compile("UserInfo\\{(\\d+):([^:}]*):([^}]*)\\}(.*)").matcher(users);
            while (m.find()) {
                Space s = new Space();
                s.id = Integer.parseInt(m.group(1));
                s.name = m.group(2);
                s.running = m.group(4).contains("running");
                s.isCurrent = (s.id == curId);
                s.hasApp = run("pm list packages --user " + s.id + " " + PKG).contains(PKG);
                found.add(s);
            }
            final int cf = curId;
            final boolean ok = !users.startsWith("[adb");
            ui.post(() -> {
                currentUid = cf;
                spaces.clear();
                spaces.addAll(found);
                if (!ok) {
                    headStatus.setTextColor(DANGER);
                    headStatus.setText("连不上本机 adbd —— 确认模拟器已开机");
                } else {
                    headStatus.setTextColor(SUB);
                    headStatus.setText("当前空间：" + nameOf(cf) + "   ·   user " + cf);
                }
                renderList();
            });
        }).start();
    }

    String nameOf(int uid) {
        for (Space s : spaces) if (s.id == uid) return label(s);
        return "未知空间";
    }

    String label(Space s) {
        if (s.id == 0) return "主空间";
        if (s.name == null || s.name.isEmpty() || s.name.equals("Owner")) return "空间 " + s.id;
        return s.name;
    }

    void renderList() {
        listBox.removeAllViews();
        if (spaces.isEmpty()) {
            TextView t = new TextView(this);
            t.setText("读不到用户列表。请确认模拟器已开机。");
            t.setTextColor(WARN);
            t.setTextSize(14);
            t.setPadding(dp(6), dp(24), dp(6), dp(24));
            listBox.addView(t);
            return;
        }
        for (Space s : spaces) listBox.addView(rowView(s));
    }

    private View rowView(Space s) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.HORIZONTAL);
        card.setGravity(Gravity.CENTER_VERTICAL);
        card.setMinimumHeight(dp(76));
        card.setBackground(card(CARD, 16));
        card.setPadding(dp(16), dp(14), dp(12), dp(14));
        LinearLayout.LayoutParams clp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        clp.bottomMargin = dp(10);
        card.setLayoutParams(clp);

        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setLayoutParams(new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        LinearLayout nameRow = new LinearLayout(this);
        nameRow.setOrientation(LinearLayout.HORIZONTAL);
        nameRow.setGravity(Gravity.CENTER_VERTICAL);
        TextView name = new TextView(this);
        name.setText(label(s));
        name.setTextSize(17);
        name.setTextColor(TEXT);
        name.setTypeface(Typeface.DEFAULT_BOLD);
        nameRow.addView(name);
        if (s.isCurrent) {
            TextView tag = new TextView(this);
            tag.setText("当前");
            tag.setTextSize(11);
            tag.setTextColor(Color.WHITE);
            tag.setBackground(card(OK, 7));
            tag.setPadding(dp(7), dp(2), dp(7), dp(2));
            LinearLayout.LayoutParams tlp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            tlp.leftMargin = dp(8);
            nameRow.addView(tag, tlp);
        }
        col.addView(nameRow);

        TextView sub = new TextView(this);
        String info = "user " + s.id + " · ";
        if (s.hasApp) {
            info += (s.isCurrent ? "运动世界已就绪" : "运动世界已装");
        } else {
            info += "运动世界未装（进入时会自动装）";
        }
        sub.setText(info);
        sub.setTextSize(12);
        sub.setTextColor(s.hasApp ? SUB : WARN);
        sub.setPadding(0, dp(5), 0, 0);
        col.addView(sub);

        card.addView(col);

        if (s.isCurrent) {
            Button go = pill("启动", true);
            go.setOnClickListener(v -> launchHere());
            card.addView(go);
        } else {
            Button sw = pill("进入此空间", false);
            sw.setOnClickListener(v -> switchTo(s));
            card.addView(sw);
        }

        card.setOnLongClickListener(v -> {
            if (s.id == 0) {
                Toast.makeText(this, "主空间不能删除", Toast.LENGTH_SHORT).show();
                return true;
            }
            new AlertDialog.Builder(this)
                    .setTitle("删除空间")
                    .setMessage("删除「" + label(s) + "」？该空间里运动世界的账号与数据会一起被清掉，不可恢复。")
                    .setNegativeButton("取消", null)
                    .setPositiveButton("删除", (d, w) -> removeSpace(s))
                    .show();
            return true;
        });
        return card;
    }

    // ---------------- 动作 ----------------

    void switchTo(final Space s) {
        if (busy) {
            Toast.makeText(this, "正在处理，稍等…", Toast.LENGTH_SHORT).show();
            return;
        }
        busy = true;
        log("正在进入「" + label(s) + "」…");
        Toast.makeText(this, "正在切换到「" + label(s) + "」", Toast.LENGTH_SHORT).show();
        new Thread(() -> {
            run("pm install-existing --user " + s.id + " " + SELF);
            String ins = run("pm install-existing --user " + s.id + " " + PKG);
            boolean okApp = !ins.toLowerCase().contains("error") && !ins.toLowerCase().contains("exception");
            log(okApp ? "  " + label(s) + "：运动世界就绪" : "  装运动世界失败：" + AdbClient.brief(ins));
            // 切用户 + 2.5 秒后在该空间拉起运动世界：后台分离执行，
            // 这样本应用（user 0）被冻结也不影响这条命令继续跑。
            // 整条链路（含 am switch-user）在 adbd 的 root shell 里前台执行。
            // 关键：这条连接全程保持打开（runLong，超时 180s），否则 App 一关通道，
            // adbd 就把 shell 会话连同里面的 am/pm 子进程一起带走 —— 之前"切了没生效"就是这么来的。
            // App 自己被系统冻结不影响它跑完；解冻后补读输出即可。
            final String L = "/data/local/tmp/space-chain.log";
            String inner = "L=" + L
                    + "; echo \"== $(date) -> user " + s.id + "\" >> $L"
                    + "; am switch-user " + s.id + " >> $L 2>&1"
                    + "; i=0; while [ $i -lt 60 ]; do [ \"$(am get-current-user)\" = \"" + s.id
                    + "\" ] && break; sleep 0.3; i=$((i+1)); done; sleep 1.0; k=0"
                    + "; while [ $k -lt 10 ]; do am start --user " + s.id + " -n " + COMP + " >> $L 2>&1; sleep 1.2"
                    + "; dumpsys activity activities 2>/dev/null | grep -m1 topResumedActivity >> $L 2>&1"
                    + "; dumpsys activity activities 2>/dev/null | grep -m1 topResumedActivity | grep -q zjwh && break"
                    + "; k=$((k+1)); done; echo \"k=$k\" >> $L";
            String sw = runLong(inner, 180000);
            log("  执行结果：" + AdbClient.tail(sw));
            String low = sw.toLowerCase();
            if (low.contains("error") || low.contains("exception")) {
                log("切换失败：" + AdbClient.brief(sw));
            } else {
                log("已切换到「" + label(s) + "」（user " + s.id + "）");
            }
            busy = false;
        }, "switch-space").start();
    }

    void launchHere() {
        log("启动运动世界…");
        new Thread(() -> {
            String out = run("am start -n " + COMP);
            log(AdbClient.brief(out));
        }, "launch").start();
    }

    void askNewSpace() {
        EditText et = new EditText(this);
        et.setHint("例如：账号C");
        et.setInputType(InputType.TYPE_CLASS_TEXT);
        int pad = dp(16);
        et.setPadding(pad, pad, pad, pad);
        new AlertDialog.Builder(this)
                .setTitle("新建空间")
                .setMessage("创建一个全新的 Android 用户空间，并把运动世界装进去（登录态完全干净）。")
                .setView(et)
                .setNegativeButton("取消", null)
                .setPositiveButton("创建", (d, w) -> {
                    String n = et.getText().toString().trim();
                    if (n.isEmpty()) n = "账号" + (spaces.size() + 1);
                    createSpace(n);
                })
                .show();
    }

    void createSpace(final String name) {
        if (busy) return;
        busy = true;
        log("新建空间「" + name + "」…");
        new Thread(() -> {
            String out = run("pm create-user " + ("'" + name.replace("'", "'\"'\"'") + "'"));
            Matcher m = Pattern.compile("id\\s+(\\d+)").matcher(out);
            if (!m.find()) {
                log("创建失败：" + AdbClient.brief(out));
                busy = false;
                return;
            }
            final int uid = Integer.parseInt(m.group(1));
            log("已创建 user " + uid + "，正在装应用…");
            run("pm install-existing --user " + uid + " " + SELF);
            String i1 = run("pm install-existing --user " + uid + " " + PKG);
            log(i1.toLowerCase().contains("error") ? "装运动世界失败：" + AdbClient.brief(i1) : "运动世界已装");
            log("空间「" + name + "」就绪，点「进入此空间」开始登录");
            busy = false;
            ui.post(this::refresh);
        }, "create-space").start();
    }

    void removeSpace(final Space s) {
        if (busy) return;
        busy = true;
        log("删除「" + label(s) + "」…");
        new Thread(() -> {
            String out = run("pm remove-user " + s.id);
            log(out.toLowerCase().contains("error") ? "删除失败：" + AdbClient.brief(out) : "已删除 user " + s.id);
            busy = false;
            ui.post(this::refresh);
        }, "remove-space").start();
    }

    /** 长按标题：自检写入 files/diag.txt */
    void diag() {
        Toast.makeText(this, "自检中…", Toast.LENGTH_SHORT).show();
        new Thread(() -> {
            StringBuilder sb = new StringBuilder();
            sb.append("adb: ").append(adbOk ? "已连接" : "未连接").append('\n');
            for (String c : new String[]{
                    "id",
                    "am get-current-user",
                    "pm list users",
                    "pm list packages --user all " + PKG,
                    "getprop ro.build.version.release"
            }) {
                sb.append("$ ").append(c).append('\n').append(run(c)).append('\n');
            }
            try {
                java.io.FileOutputStream fos = openFileOutput("diag.txt", MODE_PRIVATE);
                fos.write(sb.toString().getBytes("UTF-8"));
                fos.close();
            } catch (Exception e) {
                log("写 diag 失败: " + e);
            }
            log("自检完成");
        }, "diag").start();
    }
}
