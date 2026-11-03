/*
 * TB321FU GSI: 代替 KLC 里的 new BiometricScheduler<>(0, null)(Pixel 这一版没有这个构造函数)。
 * 参数和那个构造函数的默认值一样: 主线程 Handler, sensorType 0, 没有 GestureAvailabilityDispatcher,
 * BiometricService, 保留 50 条最近操作。
 */
package com.android.server.biometrics.sensors.face.sense;

import android.content.Context;
import android.hardware.biometrics.IBiometricService;
import android.os.Handler;
import android.os.Looper;
import android.os.ServiceManager;

import com.android.server.biometrics.sensors.BiometricScheduler;
import com.android.server.biometrics.sensors.SenseCurrentUserRetriever;

final class SenseSchedulerFactory {
    private SenseSchedulerFactory() {}

    static BiometricScheduler create() {
        final BiometricScheduler scheduler = new BiometricScheduler(
                new Handler(Looper.getMainLooper()), 0 /* sensorType */,
                null /* gestureAvailabilityDispatcher */,
                IBiometricService.Stub.asInterface(
                        ServiceManager.getService(Context.BIOMETRIC_SERVICE)),
                50 /* recentOperationsLimit */);
        scheduler.mCurrentUserRetriever = new SenseCurrentUserRetriever(scheduler);
        return scheduler;
    }
}
