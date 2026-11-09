package com.lenovo.tb321fu.torch;

import android.content.Context;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.locks.ReentrantLock;

/**
 * File channel to the herald backend (herald-apps), in this app's own device-protected files/
 * directory (/data/user_de/0/<pkg>/files): the app is directBootAware and must work on the lock
 * screen right after a reboot, before the credential-encrypted storage is unlocked.
 *
 *   1. delete a stale herald_resp
 *   2. write the command line to herald_req.tmp, then rename it to herald_req
 *   3. the backend takes herald_req away (rename or delete) within PICKUP_MS, runs the
 *      command, writes herald_resp.tmp and renames it to herald_resp
 *   4. read herald_resp and delete it
 *
 * If herald_req is still there after PICKUP_MS, nobody is serving this app (no system patch,
 * or the backend is down); the request is withdrawn and the call returns "unavailable" quickly
 * instead of waiting for the full timeout.
 *
 * There is a single request file, so calls from the activity and the summary provider are
 * serialized by one process-wide lock.
 */
final class HeraldBackend implements Backend {
    static final String REQ = "herald_req";
    static final String RESP = "herald_resp";
    static final long PICKUP_MS = 2_500;
    private static final long POLL_MS = 40;

    private static final ReentrantLock LOCK = new ReentrantLock(true);

    private final File dir;

    HeraldBackend(Context app) {
        dir = app.createDeviceProtectedStorageContext().getFilesDir();
        dir.mkdirs();
        // Let the backend (root, different uid) find and write the files.
        dir.setExecutable(true, false);
    }

    @Override
    public Resp exec(String cmd, long timeoutMs) {
        long deadline = System.currentTimeMillis() + timeoutMs;
        try {
            if (!LOCK.tryLock(timeoutMs, TimeUnit.MILLISECONDS)) {
                return new Resp(cmd, "", true, false);
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return Resp.error(cmd, "已中断");
        }
        try {
            return run(cmd, deadline);
        } finally {
            LOCK.unlock();
        }
    }

    private Resp run(String cmd, long deadline) {
        File req = new File(dir, REQ);
        File tmp = new File(dir, REQ + ".tmp");
        File resp = new File(dir, RESP);
        try {
            resp.delete();
            req.delete();
            write(tmp, cmd + "\n");
            tmp.setReadable(true, false);
            if (!tmp.renameTo(req)) {
                return Resp.error(cmd, "无法提交请求");
            }
            long sent = System.currentTimeMillis();
            boolean pickedUp = false;
            while (System.currentTimeMillis() < deadline) {
                if (resp.exists()) {
                    String out = read(resp);
                    resp.delete();
                    return Resp.parse(cmd, out);
                }
                if (!pickedUp) {
                    if (!req.exists()) {
                        pickedUp = true;
                    } else if (System.currentTimeMillis() - sent > PICKUP_MS) {
                        req.delete();
                        return new Resp(cmd, "", false, true);
                    }
                }
                Thread.sleep(POLL_MS);
            }
            req.delete();
            return new Resp(cmd, "", true, !pickedUp);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return Resp.error(cmd, "已中断");
        } catch (IOException e) {
            return Resp.error(cmd, String.valueOf(e.getMessage()));
        }
    }

    private static void write(File f, String s) throws IOException {
        try (FileOutputStream o = new FileOutputStream(f)) {
            o.write(s.getBytes(StandardCharsets.UTF_8));
        }
    }

    private static String read(File f) throws IOException {
        try (FileInputStream in = new FileInputStream(f)) {
            ByteArrayOutputStream b = new ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) b.write(buf, 0, n);
            return new String(b.toByteArray(), StandardCharsets.UTF_8);
        }
    }
}
