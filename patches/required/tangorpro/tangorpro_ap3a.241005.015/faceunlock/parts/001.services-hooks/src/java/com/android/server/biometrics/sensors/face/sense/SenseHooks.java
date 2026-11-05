/*
 * TB321FU GSI: services.jar 里 3 处 smali 补丁调用的入口, 对应 KLC 补丁里改 FaceService / AuthService 的部分。
 * 这里跑在 system_server 的 BiometricServiceRegistry 线程上, 抛出去就是 system_server 崩溃循环, 所以全部兜住。
 */
package com.android.server.biometrics.sensors.face.sense;

import android.app.ActivityThread;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.hardware.biometrics.SensorProperties;
import android.hardware.face.FaceSensorProperties;
import android.hardware.face.FaceSensorPropertiesInternal;
import android.os.Binder;
import android.os.Process;
import android.util.Slog;

import com.android.server.biometrics.sensors.face.FaceService;

import java.util.ArrayList;
import java.util.List;

public final class SenseHooks {
    private static final String TAG = "SenseHooks";
    private static final String PERM_INTERNAL = "android.permission.USE_BIOMETRIC_INTERNAL";
    private static final String PERM_MANAGE = "android.permission.MANAGE_BIOMETRIC";
    private static final String PKG_SENSE = "com.android.faceunlock";

    private SenseHooks() {}

    /**
     * 代替 Face/Biometric/Auth Service AIDL 层的 USE_BIOMETRIC_INTERNAL / MANAGE_BIOMETRIC 校验。
     * 平板上两个权限都是 signature(不是 signature|privileged), 自签名的 ParanoidSense 两个都拿不到,
     * privapp 白名单对 signature 无效。放行条件:
     *   1. 调用方是 system/root/本进程(system_server)
     *   2. 调用方真的持有 USE_BIOMETRIC_INTERNAL 或 MANAGE_BIOMETRIC
     *   3. 调用方 uid 对应的包里有 com.android.faceunlock, 并且它是系统 priv-app(FLAG_SYSTEM + isPrivilegedApp)
     * 不走 Context.enforceCallingOrSelfPermission(perm, ...), 否则 PermissionChecker 还是会拒。
     */
    public static void enforceInternal() {
        final int uid = Binder.getCallingUid();
        final int pid = Binder.getCallingPid();
        if (allowed(uid, pid)) return;
        throw new SecurityException("Permission Denial: uid=" + uid + " pid=" + pid
                + " requires " + PERM_INTERNAL + " or " + PERM_MANAGE
                + " (and is not " + PKG_SENSE + " priv-app)");
    }

    /** 原 Utils.hasInternalPermission 的放宽版。 */
    public static boolean hasInternal(Context ctx) {
        return allowed(Binder.getCallingUid(), Binder.getCallingPid());
    }

    private static boolean allowed(int uid, int pid) {
        if (uid == Process.SYSTEM_UID || uid == 0 || uid == Process.myUid()) return true;
        final Context ctx = systemContext();
        if (ctx == null) return false;
        if (ctx.checkPermission(PERM_INTERNAL, pid, uid) == PackageManager.PERMISSION_GRANTED) return true;
        if (ctx.checkPermission(PERM_MANAGE, pid, uid) == PackageManager.PERMISSION_GRANTED) return true;
        return isSensePrivApp(ctx, uid);
    }

    /** uid 的包里有 com.android.faceunlock, 并且它是系统 priv-app。system_server 查 pm 要清 identity。 */
    private static boolean isSensePrivApp(Context ctx, int uid) {
        final PackageManager pm = ctx.getPackageManager();
        if (pm == null) return false;
        final long token = Binder.clearCallingIdentity();
        try {
            final String[] pkgs = pm.getPackagesForUid(uid);
            if (pkgs == null) return false;
            boolean hasSense = false;
            for (String p : pkgs) {
                if (PKG_SENSE.equals(p)) { hasSense = true; break; }
            }
            if (!hasSense) return false;
            final ApplicationInfo ai = pm.getApplicationInfo(PKG_SENSE, 0);
            final boolean system = (ai.flags & ApplicationInfo.FLAG_SYSTEM) != 0;
            final boolean priv = ai.isPrivilegedApp();
            if (system && priv) return true;
            Slog.w(TAG, PKG_SENSE + " present for uid " + uid
                    + " but not priv-app (system=" + system + " priv=" + priv + ")");
            return false;
        } catch (Throwable t) {
            Slog.e(TAG, "isSensePrivApp failed for uid " + uid, t);
            return false;
        } finally {
            Binder.restoreCallingIdentity(token);
        }
    }

    private static Context systemContext() {
        try {
            ActivityThread t = ActivityThread.currentActivityThread();
            if (t == null) return null;
            Context c = t.getSystemContext();
            return c != null ? c : t.getApplication();
        } catch (Throwable e) {
            return null;
        }
    }

    /** AuthService.registerFaceSensors / FaceService.registerAuthenticators: 没有人脸 HAL 也继续注册。 */
    public static boolean canUseProvider() {
        try {
            return SenseUtils.canUseProvider();
        } catch (Throwable t) {
            Slog.e(TAG, "canUseProvider failed, face unlock disabled", t);
            return false;
        }
    }

    /** FaceService$FaceServiceWrapper.getProviders: 开了 ro.face.sense_service 就只用 SenseProvider, 否则返回 null 走原逻辑。 */
    public static List getProviders(FaceService service) {
        if (!canUseProvider()) {
            return null;
        }
        try {
            final FaceSensorPropertiesInternal props = new FaceSensorPropertiesInternal(
                    SenseProvider.DEVICE_ID,
                    SensorProperties.STRENGTH_WEAK,
                    1 /* maxEnrollmentsPerUser */,
                    new ArrayList<>(),
                    FaceSensorProperties.TYPE_RGB,
                    false /* supportsFaceDetection */,
                    false /* supportsSelfIllumination */,
                    false /* resetLockoutRequiresChallenge */);
            final List providers = new ArrayList();
            providers.add(new SenseProvider(service.getContext(), service.mBiometricStateCallback,
                    props, service.mLockoutResetDispatcher));
            Slog.i(TAG, "SenseProvider registered");
            return providers;
        } catch (Throwable t) {
            Slog.e(TAG, "SenseProvider init failed, face unlock disabled", t);
            return new ArrayList();
        }
    }
}
