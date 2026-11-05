/*
 * TB321FU GSI: ParanoidSense 移植用.
 * Pixel 这一版 BiometricScheduler.checkCurrentUserAndStartNextOperation() 会无条件调用 mCurrentUserRetriever.get(),
 * KLC 的补丁是在那里加判空, 直接 startNextOperationIfIdle()。这里不改 BiometricScheduler,
 * 而是给它一个总是返回队首操作目标用户的 retriever, 走的是同一条路径(用户相同 -> startNextOperationIfIdle)。
 * 放在 sensors 包里是为了能读包内可见的 mPendingOperations。
 */
package com.android.server.biometrics.sensors;

import android.os.UserHandle;

import java.util.function.Supplier;

public final class SenseCurrentUserRetriever implements Supplier<Integer> {
    private final BiometricScheduler mScheduler;

    public SenseCurrentUserRetriever(BiometricScheduler scheduler) {
        mScheduler = scheduler;
    }

    @Override
    public Integer get() {
        final Object first = mScheduler.mPendingOperations.peekFirst();
        return first != null
                ? ((BiometricSchedulerOperation) first).getTargetUserId()
                : UserHandle.USER_NULL;
    }
}
