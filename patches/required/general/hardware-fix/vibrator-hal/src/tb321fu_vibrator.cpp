// tb321fu-vibrator: android.hardware.vibrator.IVibratorManager/default (AIDL V2) for the
// Lenovo TB321FU (Legion Y700 Gen 3) dual Awinic AW86937 LRAs.
//
// Why: the stock vendor HAL (vendor.qti.hardware.vibrator.service) only uses the input
// force-feedback path for devices named "qcom-hv-haptics"/"qti-haptics". The Awinic driver
// registers its two motors as "aw-haptic-hv", so the vendor HAL falls back to the LED
// path: no primitives, no compose, and the framework sees only one vibrator.
//
// How: the Awinic driver's input FF interface (decoded from haptic.ko, 2026-11-09):
//   FF_CONSTANT, replay.length = N ms     -> continuous drive for N ms (driver mode 5)
//   FF_PERIODIC + FF_CUSTOM, data[0] = k  -> k in 1..ram_num-1: one-shot RAM waveform k with brake
//                                            k = 4: 45 ms, k = 5: 13 ms, k >= 6: RTP file
//   EV_FF code = effect id, value 1/0     -> play / stop the LAST UPLOADED effect (id is ignored)
//   EV_FF code = FF_GAIN, value 0..0x7fff -> gain register 0..0x80 (100 %)
// RAM waveforms (24 kHz): 1 = 16 ms 3 cycles @ f0 (heavy), 2 = 11.4 ms 2 cycles (click),
//                         3 = 10.3 ms ~290 Hz (tick)
//
// Only the NDK is needed to build. Binder marshalling is written by hand against the
// framework's own Java stubs (transaction codes / parcel layout taken from framework.jar).
// Platform-only libbinder_ndk entry points (AServiceManager_*, ABinderProcess_*) are
// resolved with dlsym so the NDK stub library is enough to link.

#include <android/binder_ibinder.h>
#include <android/binder_parcel.h>
#include <android/binder_status.h>
#include <android/log.h>
#include <sys/system_properties.h>

#include <dirent.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <climits>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#define TAG "tb321fu-vibrator"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

using namespace std::chrono_literals;
using Clock = std::chrono::steady_clock;

namespace {

// ---------------------------------------------------------------- AIDL constants (framework.jar)
constexpr const char* kManagerDescriptor = "android.hardware.vibrator.IVibratorManager";
constexpr const char* kVibratorDescriptor = "android.hardware.vibrator.IVibrator";
constexpr const char* kCallbackDescriptor = "android.hardware.vibrator.IVibratorCallback";
constexpr const char* kInstance = "android.hardware.vibrator.IVibratorManager/default";
constexpr int32_t kInterfaceVersion = 2;
constexpr const char* kInterfaceHash = "notfrozen";
constexpr transaction_code_t TX_GET_INTERFACE_VERSION = 16777215;
constexpr transaction_code_t TX_GET_INTERFACE_HASH = 16777214;

// IVibrator transactions
enum : transaction_code_t {
    V_GET_CAPABILITIES = 1, V_OFF = 2, V_ON = 3, V_PERFORM = 4, V_GET_SUPPORTED_EFFECTS = 5,
    V_SET_AMPLITUDE = 6, V_SET_EXTERNAL_CONTROL = 7, V_GET_COMPOSITION_DELAY_MAX = 8,
    V_GET_COMPOSITION_SIZE_MAX = 9, V_GET_SUPPORTED_PRIMITIVES = 10, V_GET_PRIMITIVE_DURATION = 11,
    V_COMPOSE = 12, V_GET_RESONANT_FREQUENCY = 16,
};
// IVibratorManager transactions
enum : transaction_code_t {
    M_GET_CAPABILITIES = 1, M_GET_VIBRATOR_IDS = 2, M_GET_VIBRATOR = 3, M_PREPARE_SYNCED = 4,
    M_TRIGGER_SYNCED = 5, M_CANCEL_SYNCED = 6,
};
constexpr transaction_code_t CB_ON_COMPLETE = 1;  // oneway

// IVibrator capabilities
constexpr int32_t CAP_ON_CALLBACK = 1, CAP_PERFORM_CALLBACK = 2, CAP_AMPLITUDE_CONTROL = 4,
                  CAP_COMPOSE_EFFECTS = 32;  // GET_RESONANT_FREQUENCY (128) deliberately not reported
// IVibratorManager capabilities
constexpr int32_t MCAP_SYNC = 1, MCAP_PREPARE_ON = 2, MCAP_PREPARE_PERFORM = 4,
                  MCAP_PREPARE_COMPOSE = 8, MCAP_MIXED_TRIGGER_ON = 16,
                  MCAP_MIXED_TRIGGER_PERFORM = 32, MCAP_MIXED_TRIGGER_COMPOSE = 64,
                  MCAP_TRIGGER_CALLBACK = 128;

// Effect / EffectStrength / CompositePrimitive
enum Effect : int32_t { CLICK = 0, DOUBLE_CLICK = 1, TICK = 2, THUD = 3, POP = 4, HEAVY_CLICK = 5,
                        TEXTURE_TICK = 21 };
enum Strength : int8_t { LIGHT = 0, MEDIUM = 1, STRONG = 2 };
enum Primitive : int32_t { P_NOOP = 0, P_CLICK = 1, P_THUD = 2, P_SPIN = 3, P_QUICK_RISE = 4,
                           P_SLOW_RISE = 5, P_QUICK_FALL = 6, P_LIGHT_TICK = 7, P_LOW_TICK = 8 };

// ---------------------------------------------------------------- platform-only libbinder_ndk
struct Plat {
    binder_exception_t (*addService)(AIBinder*, const char*) = nullptr;
    bool (*setThreadPoolMaxThreadCount)(uint32_t) = nullptr;
    void (*startThreadPool)() = nullptr;
    void (*joinThreadPool)() = nullptr;
    bool load() {
        void* h = dlopen("libbinder_ndk.so", RTLD_NOW);
        if (!h) { LOGE("dlopen libbinder_ndk: %s", dlerror()); return false; }
        addService = reinterpret_cast<decltype(addService)>(dlsym(h, "AServiceManager_addService"));
        setThreadPoolMaxThreadCount = reinterpret_cast<decltype(setThreadPoolMaxThreadCount)>(
                dlsym(h, "ABinderProcess_setThreadPoolMaxThreadCount"));
        startThreadPool = reinterpret_cast<decltype(startThreadPool)>(dlsym(h, "ABinderProcess_startThreadPool"));
        joinThreadPool = reinterpret_cast<decltype(joinThreadPool)>(dlsym(h, "ABinderProcess_joinThreadPool"));
        return addService && setThreadPoolMaxThreadCount && startThreadPool && joinThreadPool;
    }
} gPlat;

// ---------------------------------------------------------------- tunables (system properties)
int propInt(const char* name, int def) {
    char v[PROP_VALUE_MAX] = {};
    if (__system_property_get(name, v) <= 0) return def;
    char* end = nullptr;
    long r = strtol(v, &end, 10);
    return (end && end != v) ? static_cast<int>(r) : def;
}
// persist.tb321fu.vibrator.gain_max   0..100, ceiling for every effect (default 100 = gain 0x80)
// persist.tb321fu.vibrator.ramps      1 = expose SPIN/QUICK_RISE/SLOW_RISE/QUICK_FALL (default 1)
// persist.tb321fu.vibrator.motors     3 = both (default), 1 = left only, 2 = right only

// ---------------------------------------------------------------- callback helper
AIBinder_Class* gCallbackClass = nullptr;

struct Callback {  // owns one strong ref to an IVibratorCallback binder (may be null)
    AIBinder* b = nullptr;
    Callback() = default;
    explicit Callback(AIBinder* binder) : b(binder) {}  // takes ownership
    Callback(const Callback& o) : b(o.b) { if (b) AIBinder_incStrong(b); }
    Callback& operator=(const Callback& o) {
        if (this != &o) { reset(); b = o.b; if (b) AIBinder_incStrong(b); }
        return *this;
    }
    ~Callback() { reset(); }
    void reset() { if (b) AIBinder_decStrong(b); b = nullptr; }
    explicit operator bool() const { return b != nullptr; }
    void fire() const {
        if (!b) return;
        if (!AIBinder_associateClass(b, gCallbackClass)) {
            LOGW("callback is not an IVibratorCallback");
        }
        AParcel* in = nullptr;
        if (AIBinder_prepareTransaction(b, &in) != STATUS_OK) { LOGW("prepareTransaction failed"); return; }
        AParcel* out = nullptr;
        binder_status_t st = AIBinder_transact(b, CB_ON_COMPLETE, &in, &out, FLAG_ONEWAY);
        if (out) AParcel_delete(out);
        if (st != STATUS_OK) LOGW("onComplete failed: %d", st);
    }
};

// RAM waveform play time incl. brake/settle margin (1 = heavy 16 ms, 2 = click 11.4 ms, 3 = tick 10.3 ms)
constexpr int ramMsOf(int16_t w) { return w == 1 ? 20 : w == 2 ? 15 : 13; }

// ---------------------------------------------------------------- one Awinic motor (input FF)
class Motor {
  public:
    Motor(int id, const char* name, std::string dev) : mId(id), mName(name), mDev(std::move(dev)) {}

    bool open() {
        mFd = ::open(mDev.c_str(), O_RDWR | O_CLOEXEC);
        if (mFd < 0) { LOGE("%s: open %s: %s", mName, mDev.c_str(), strerror(errno)); return false; }
        mThread = std::thread([this] { loop(); });
        LOGI("%s motor on %s", mName, mDev.c_str());
        return true;
    }
    int id() const { return mId; }
    const char* name() const { return mName; }

    // ---- low level, call with mHw held
    // haptic_hv has ONE force-feedback slot per motor, and the input core refuses to change the
    // type of an uploaded effect (EINVAL). So: free the slot before uploading a different type,
    // and never ask for a new slot while still holding the old one (that is ENOSPC: test-v2.3,
    // every FF_CONSTANT one-shot failed once a RAM click had taken the slot).
    void eraseLocked() {
        if (mEffectId == -1) return;
        if (ioctl(mFd, EVIOCRMFF, static_cast<unsigned long>(mEffectId)) < 0)
            LOGW("%s: EVIOCRMFF %d: %s", mName, mEffectId, strerror(errno));
        mEffectId = -1;
        mEffectType = -1;
        mPlayUntil = Clock::time_point{};
    }
    bool uploadLocked(ff_effect& e) {
        if (mEffectId != -1 && mEffectType != e.type) eraseLocked();
        e.id = mEffectId;
        if (ioctl(mFd, EVIOCSFF, &e) == 0) {
            mEffectId = e.id;
            mEffectType = e.type;
            return true;
        }
        int err = errno;
        if (mEffectId != -1) {  // slot dropped or rejected: free it, then take a fresh one
            eraseLocked();
            e.id = -1;
            if (ioctl(mFd, EVIOCSFF, &e) == 0) {
                mEffectId = e.id;
                mEffectType = e.type;
                return true;
            }
            err = errno;
        }
        LOGE("%s: EVIOCSFF type 0x%x: %s", mName, e.type, strerror(err));
        return false;
    }
    bool writeEv(uint16_t code, int32_t value) {
        input_event ev{};
        ev.type = EV_FF;
        ev.code = code;
        ev.value = value;
        return ::write(mFd, &ev, sizeof(ev)) == static_cast<ssize_t>(sizeof(ev));
    }
    void gainLocked(float g) {
        g = std::clamp(g, 0.0f, 1.0f) * mGainCeiling;
        int v = static_cast<int>(std::lround(g * 0x7fff));
        if (v != mLastGain) { writeEv(FF_GAIN, v); mLastGain = v; }
    }
    bool constantLocked(uint32_t ms) {
        ff_effect e{};
        e.type = FF_CONSTANT;
        e.replay.length = static_cast<uint16_t>(std::min<uint32_t>(ms, 0xffff));
        e.u.constant.level = 0x7fff;
        if (!uploadLocked(e) || !writeEv(static_cast<uint16_t>(mEffectId), 1)) return false;
        mPlayUntil = Clock::now() + std::chrono::milliseconds(e.replay.length);
        return true;
    }
    bool ramLocked(int16_t wave) {
        int16_t data[1] = {wave};
        ff_effect e{};
        e.type = FF_PERIODIC;
        e.u.periodic.waveform = FF_CUSTOM;
        e.u.periodic.magnitude = 0x7fff;
        e.u.periodic.custom_len = 1;
        e.u.periodic.custom_data = data;
        if (!uploadLocked(e) || !writeEv(static_cast<uint16_t>(mEffectId), 1)) return false;
        mPlayUntil = Clock::now() + std::chrono::milliseconds(ramMsOf(wave));
        return true;
    }
    // Only stop a motor that may still be running: the driver logs every stop, and test-v2.3 sent
    // twice as many stops as plays (dmesg flooded). FF_CONSTANT / RAM effects end by themselves.
    void stopLocked() {
        if (mEffectId != -1 && Clock::now() < mPlayUntil) writeEv(static_cast<uint16_t>(mEffectId), 0);
        mPlayUntil = Clock::time_point{};
    }

    // ---- job runner: one job at a time; a new job (or off) cancels the running one
    using Job = std::function<void(Motor&, uint64_t gen)>;
    void run(Job job, Callback cb) {
        std::lock_guard<std::mutex> l(mJobMu);
        ++mGen;
        mJob = std::move(job);
        mJobCb = std::move(cb);
        mVibrating = true;
        mCv.notify_all();
    }
    void cancel() {
        {
            std::lock_guard<std::mutex> l(mJobMu);
            ++mGen;
            mJob = nullptr;
            mJobCb.reset();
            mCv.notify_all();
        }
        std::lock_guard<std::mutex> h(mHw);
        stopLocked();
        mVibrating = false;
    }
    // sleeps up to d; false if the job was cancelled/replaced meanwhile
    bool sleepFor(std::chrono::microseconds d, uint64_t gen) {
        std::unique_lock<std::mutex> l(mJobMu);
        return !mCv.wait_for(l, d, [&] { return mGen != gen || mQuit; });
    }
    bool current(uint64_t gen) {
        std::lock_guard<std::mutex> l(mJobMu);
        return mGen == gen && !mQuit;
    }

    std::mutex mHw;  // serialises ioctl/write on the fd
    float mAmplitude = 1.0f;
    float mGainCeiling = 1.0f;
    std::atomic<bool> mVibrating{false};
    std::atomic<bool> mPrepared{false};
    Job mPendingJob;  // held while prepared for a synced trigger
    Callback mPendingCb;

  private:
    void loop() {
        std::unique_lock<std::mutex> l(mJobMu);
        while (!mQuit) {
            mCv.wait(l, [&] { return mJob != nullptr || mQuit; });
            if (mQuit) break;
            Job job = std::move(mJob);
            mJob = nullptr;
            Callback cb = std::move(mJobCb);
            mJobCb.reset();
            uint64_t gen = mGen;
            l.unlock();
            mVibrating = true;
            job(*this, gen);
            bool finished = current(gen);
            if (finished) {
                mVibrating = false;
                cb.fire();
            }
            l.lock();
        }
    }

    int mId;
    const char* mName;
    std::string mDev;
    int mFd = -1;
    int16_t mEffectId = -1;
    int mEffectType = -1;            // type of the effect in mEffectId (FF_CONSTANT / FF_PERIODIC)
    Clock::time_point mPlayUntil{};  // when the last played effect ends on its own
    int mLastGain = -1;
    std::mutex mJobMu;
    std::condition_variable mCv;
    uint64_t mGen = 0;
    Job mJob;
    Callback mJobCb;
    bool mQuit = false;
    std::thread mThread;
};

// ---------------------------------------------------------------- effect tables
constexpr int16_t RAM_HEAVY = 1, RAM_CLICK = 2, RAM_TICK = 3;
int ramMs(int16_t w) { return ramMsOf(w); }

struct Shot {  // one RAM shot
    int16_t wave;
    float gain;
};

bool rampsEnabled() { return propInt("persist.tb321fu.vibrator.ramps", 1) != 0; }

std::vector<int32_t> supportedPrimitives() {
    std::vector<int32_t> p = {P_NOOP, P_CLICK, P_THUD, P_LIGHT_TICK, P_LOW_TICK};
    if (rampsEnabled()) {
        p.push_back(P_SPIN);
        p.push_back(P_QUICK_RISE);
        p.push_back(P_SLOW_RISE);
        p.push_back(P_QUICK_FALL);
    }
    std::sort(p.begin(), p.end());
    return p;
}
bool primitiveSupported(int32_t p) {
    auto v = supportedPrimitives();
    return std::find(v.begin(), v.end(), p) != v.end();
}
int primitiveMs(int32_t p) {
    switch (p) {
        case P_NOOP: return 0;
        case P_CLICK: return ramMs(RAM_CLICK);
        case P_THUD: return ramMs(RAM_HEAVY);
        case P_LIGHT_TICK: return ramMs(RAM_TICK);
        case P_LOW_TICK: return ramMs(RAM_HEAVY);
        case P_SPIN: return 90;
        case P_QUICK_RISE: return 70;
        case P_SLOW_RISE: return 220;
        case P_QUICK_FALL: return 70;
    }
    return 0;
}

// Plays one primitive on the motor, blocking for its duration. false = cancelled.
bool playPrimitive(Motor& m, int32_t p, float scale, uint64_t gen) {
    scale = std::clamp(scale, 0.0f, 1.0f);
    auto shot = [&](int16_t wave, float g) {
        {
            std::lock_guard<std::mutex> h(m.mHw);
            if (!m.current(gen)) return false;
            m.gainLocked(g);
            m.ramLocked(wave);
        }
        return m.sleepFor(std::chrono::milliseconds(ramMs(wave)), gen);
    };
    // amplitude envelope on the continuous drive, 5 ms steps
    auto ramp = [&](int ms, const std::function<float(float)>& env) {
        {
            std::lock_guard<std::mutex> h(m.mHw);
            if (!m.current(gen)) return false;
            m.gainLocked(env(0.0f) * scale);
            m.constantLocked(static_cast<uint32_t>(ms));
        }
        auto t0 = Clock::now();
        for (;;) {
            if (!m.sleepFor(5ms, gen)) {
                std::lock_guard<std::mutex> h(m.mHw);
                m.stopLocked();
                return false;
            }
            float t = std::chrono::duration<float, std::milli>(Clock::now() - t0).count() / ms;
            if (t >= 1.0f) break;
            std::lock_guard<std::mutex> h(m.mHw);
            if (!m.current(gen)) return false;
            m.gainLocked(env(t) * scale);
        }
        std::lock_guard<std::mutex> h(m.mHw);
        if (m.current(gen)) m.stopLocked();
        return true;
    };
    switch (p) {
        case P_NOOP: return true;
        case P_CLICK: return shot(RAM_CLICK, scale);
        case P_THUD: return shot(RAM_HEAVY, scale);
        case P_LIGHT_TICK: return shot(RAM_TICK, scale * 0.6f);
        case P_LOW_TICK: return shot(RAM_HEAVY, scale * 0.45f);
        case P_SPIN: return ramp(primitiveMs(p), [](float t) { return t < 0.5f ? t * 2 : (1 - t) * 2; });
        case P_QUICK_RISE: return ramp(primitiveMs(p), [](float t) { return t * t; });
        case P_SLOW_RISE: return ramp(primitiveMs(p), [](float t) { return t; });
        case P_QUICK_FALL: return ramp(primitiveMs(p), [](float t) { return (1 - t) * (1 - t); });
    }
    return true;
}

float strengthGain(int8_t s) { return s == LIGHT ? 0.55f : s == MEDIUM ? 0.8f : 1.0f; }

// effect -> list of {delay before, shot}; empty = unsupported
std::vector<std::pair<int, Shot>> effectShots(int32_t effect, int8_t strength) {
    float g = strengthGain(strength);
    switch (effect) {
        case CLICK: return {{0, {RAM_CLICK, g}}};
        case DOUBLE_CLICK: return {{0, {RAM_CLICK, g}}, {85, {RAM_CLICK, g}}};
        case TICK: return {{0, {RAM_TICK, g}}};
        case TEXTURE_TICK: return {{0, {RAM_TICK, g * 0.5f}}};
        case THUD: return {{0, {RAM_HEAVY, g}}};
        case POP: return {{0, {RAM_TICK, std::min(1.0f, g * 1.2f)}}};
        case HEAVY_CLICK: return {{0, {RAM_HEAVY, std::min(1.0f, g * 1.15f)}}};
    }
    return {};
}
const std::vector<int32_t> kSupportedEffects = {CLICK, DOUBLE_CLICK, TICK, THUD, POP, HEAVY_CLICK, TEXTURE_TICK};

// ---------------------------------------------------------------- service state
std::vector<Motor*> gMotors;  // index = vibrator id
float gResonantHz = 170.0f;
std::mutex gSyncMu;
bool gSyncPrepared = false;
std::vector<int32_t> gSyncIds;

Motor* motorById(int32_t id) {
    return (id >= 0 && id < static_cast<int32_t>(gMotors.size())) ? gMotors[id] : nullptr;
}

// ---------------------------------------------------------------- parcel helpers
bool allocInts(void* arrayData, int32_t length, int32_t** out) {
    auto* v = static_cast<std::vector<int32_t>*>(arrayData);
    if (length < 0) { v->clear(); *out = nullptr; return true; }
    v->resize(length);
    *out = v->data();
    return true;
}
binder_status_t readIntArray(const AParcel* in, std::vector<int32_t>* v) {
    return AParcel_readInt32Array(in, v, [](void* d, int32_t len, int32_t** buf) { return allocInts(d, len, buf); });
}
binder_status_t replyOk(AParcel* out) {
    AStatus* s = AStatus_newOk();
    binder_status_t r = AParcel_writeStatusHeader(out, s);
    AStatus_delete(s);
    return r;
}
binder_status_t replyEx(AParcel* out, binder_exception_t ex, const char* msg) {
    AStatus* s = AStatus_fromExceptionCodeWithMessage(ex, msg);
    binder_status_t r = AParcel_writeStatusHeader(out, s);
    AStatus_delete(s);
    return r;
}
binder_status_t replyInt(AParcel* out, int32_t v) {
    binder_status_t r = replyOk(out);
    return r == STATUS_OK ? AParcel_writeInt32(out, v) : r;
}
binder_status_t replyInts(AParcel* out, const std::vector<int32_t>& v) {
    binder_status_t r = replyOk(out);
    return r == STATUS_OK ? AParcel_writeInt32Array(out, v.data(), static_cast<int32_t>(v.size())) : r;
}
binder_status_t replyFloat(AParcel* out, float v) {
    binder_status_t r = replyOk(out);
    return r == STATUS_OK ? AParcel_writeFloat(out, v) : r;
}
binder_status_t replyString(AParcel* out, const char* s) {
    binder_status_t r = replyOk(out);
    return r == STATUS_OK ? AParcel_writeString(out, s, static_cast<int32_t>(strlen(s))) : r;
}
Callback readCallback(const AParcel* in) {
    AIBinder* b = nullptr;
    if (AParcel_readStrongBinder(in, &b) != STATUS_OK) return Callback();
    return Callback(b);
}

struct CompositeEffect {
    int32_t delayMs = 0;
    int32_t primitive = 0;
    float scale = 0;
};
// Java Parcel.writeTypedArray: int32 n, then per element int32 1 (non-null) + parcelable
// parcelable = int32 size (incl. itself) + delayMs + primitive + scale
binder_status_t readComposite(const AParcel* in, std::vector<CompositeEffect>* v) {
    int32_t n = 0;
    binder_status_t r = AParcel_readInt32(in, &n);
    if (r != STATUS_OK) return r;
    if (n < 0 || n > 4096) return STATUS_BAD_VALUE;
    v->clear();
    for (int32_t i = 0; i < n; ++i) {
        int32_t present = 0;
        if ((r = AParcel_readInt32(in, &present)) != STATUS_OK) return r;
        if (!present) return STATUS_UNEXPECTED_NULL;
        int32_t start = AParcel_getDataPosition(in);
        int32_t size = 0;
        if ((r = AParcel_readInt32(in, &size)) != STATUS_OK) return r;
        if (size < 4) return STATUS_BAD_VALUE;
        CompositeEffect e;
        if (AParcel_getDataPosition(in) - start < size) AParcel_readInt32(in, &e.delayMs);
        if (AParcel_getDataPosition(in) - start < size) AParcel_readInt32(in, &e.primitive);
        if (AParcel_getDataPosition(in) - start < size) AParcel_readFloat(in, &e.scale);
        if ((r = AParcel_setDataPosition(in, start + size)) != STATUS_OK) return r;
        v->push_back(e);
    }
    return STATUS_OK;
}

// ---------------------------------------------------------------- vibrator commands
// Every command builds a Job. If the motor is prepared for a synced trigger the job is
// parked until triggerSynced(), otherwise it starts now.
void submit(Motor& m, Motor::Job job, Callback cb) {
    std::lock_guard<std::mutex> l(gSyncMu);
    if (m.mPrepared) {
        m.mPendingJob = std::move(job);
        m.mPendingCb = std::move(cb);
        return;
    }
    m.run(std::move(job), std::move(cb));
}

// Apps' short one-shots (B站 / YouTube long-press, IME key feedback with a custom strength) are
// 20-30 ms at low amplitude: a 30 ms FF_CONSTANT barely spins an LRA up. Play them as a RAM
// waveform instead (the vendor driver uses the same 20/30/60 ms split, DT aw8693x_duration_time),
// keeping the app's amplitude but with a floor so it is always felt.
//   persist.tb321fu.vibrator.short_ms     one-shots up to this long use RAM (default 30, 0 = off)
//   persist.tb321fu.vibrator.short_floor  gain floor in % for those (default 35)
Motor::Job onJob(int32_t timeoutMs) {
    int shortMs = std::clamp(propInt("persist.tb321fu.vibrator.short_ms", 30), 0, 60);
    if (timeoutMs > 0 && timeoutMs <= shortMs) {
        float floor = std::clamp(propInt("persist.tb321fu.vibrator.short_floor", 35), 0, 100) / 100.0f;
        int16_t wave = timeoutMs <= 15 ? RAM_TICK : RAM_CLICK;
        return [wave, floor](Motor& m, uint64_t gen) {
            {
                std::lock_guard<std::mutex> h(m.mHw);
                if (!m.current(gen)) return;
                m.gainLocked(floor + (1.0f - floor) * m.mAmplitude);
                m.ramLocked(wave);
            }
            m.sleepFor(std::chrono::milliseconds(ramMs(wave)), gen);
        };
    }
    return [timeoutMs](Motor& m, uint64_t gen) {
        int32_t left = std::max(timeoutMs, 0);
        while (left > 0) {
            int32_t chunk = std::min(left, 60000);
            {
                std::lock_guard<std::mutex> h(m.mHw);
                if (!m.current(gen)) return;
                m.gainLocked(m.mAmplitude);
                m.constantLocked(static_cast<uint32_t>(chunk));
            }
            if (!m.sleepFor(std::chrono::milliseconds(chunk), gen)) return;
            left -= chunk;
        }
        std::lock_guard<std::mutex> h(m.mHw);
        if (m.current(gen)) m.stopLocked();
    };
}

Motor::Job shotsJob(std::vector<std::pair<int, Shot>> shots) {
    return [shots = std::move(shots)](Motor& m, uint64_t gen) {
        for (const auto& [delay, s] : shots) {
            if (delay > 0 && !m.sleepFor(std::chrono::milliseconds(delay), gen)) return;
            {
                std::lock_guard<std::mutex> h(m.mHw);
                if (!m.current(gen)) return;
                m.gainLocked(s.gain);
                m.ramLocked(s.wave);
            }
            if (!m.sleepFor(std::chrono::milliseconds(ramMs(s.wave)), gen)) return;
        }
    };
}
int shotsMs(const std::vector<std::pair<int, Shot>>& shots) {
    int t = 0;
    for (const auto& [delay, s] : shots) t += delay + ramMs(s.wave);
    return t;
}

Motor::Job composeJob(std::vector<CompositeEffect> effects) {
    return [effects = std::move(effects)](Motor& m, uint64_t gen) {
        for (const auto& e : effects) {
            if (e.delayMs > 0 && !m.sleepFor(std::chrono::milliseconds(e.delayMs), gen)) return;
            if (!playPrimitive(m, e.primitive, e.scale, gen)) return;
        }
    };
}

// ---------------------------------------------------------------- IVibrator binder
AIBinder_Class* gVibratorClass = nullptr;
AIBinder_Class* gManagerClass = nullptr;
std::vector<AIBinder*> gVibratorBinders;

int32_t vibratorCaps() {
    // No CAP_GET_RESONANT_FREQUENCY: without a frequency profile (PWLE) the framework logs
    // "VibratorInfo: Invalid frequency profile"; nothing uses f0 alone.
    return CAP_ON_CALLBACK | CAP_PERFORM_CALLBACK | CAP_AMPLITUDE_CONTROL | CAP_COMPOSE_EFFECTS;
}

binder_status_t vibratorTransact(AIBinder* binder, transaction_code_t code, const AParcel* in, AParcel* out) {
    Motor* m = static_cast<Motor*>(AIBinder_getUserData(binder));
    if (!m) return STATUS_UNEXPECTED_NULL;
    switch (code) {
        case TX_GET_INTERFACE_VERSION: return replyInt(out, kInterfaceVersion);
        case TX_GET_INTERFACE_HASH: return replyString(out, kInterfaceHash);
        case V_GET_CAPABILITIES: return replyInt(out, vibratorCaps());
        case V_OFF:
            m->cancel();
            return replyOk(out);
        case V_ON: {
            int32_t ms = 0;
            binder_status_t r = AParcel_readInt32(in, &ms);
            if (r != STATUS_OK) return r;
            Callback cb = readCallback(in);
            submit(*m, onJob(ms), std::move(cb));
            return replyOk(out);
        }
        case V_PERFORM: {
            int32_t effect = 0;
            int8_t strength = 0;
            binder_status_t r = AParcel_readInt32(in, &effect);
            if (r == STATUS_OK) r = AParcel_readByte(in, &strength);
            if (r != STATUS_OK) return r;
            Callback cb = readCallback(in);
            auto shots = effectShots(effect, strength);
            if (shots.empty()) return replyEx(out, EX_UNSUPPORTED_OPERATION, "effect not supported");
            int ms = shotsMs(shots);
            submit(*m, shotsJob(std::move(shots)), std::move(cb));
            return replyInt(out, ms);
        }
        case V_GET_SUPPORTED_EFFECTS: return replyInts(out, kSupportedEffects);
        case V_SET_AMPLITUDE: {
            float a = 0;
            binder_status_t r = AParcel_readFloat(in, &a);
            if (r != STATUS_OK) return r;
            if (!(a > 0.0f && a <= 1.0f)) return replyEx(out, EX_ILLEGAL_ARGUMENT, "amplitude");
            m->mAmplitude = a;
            if (m->mVibrating) {
                std::lock_guard<std::mutex> h(m->mHw);
                m->gainLocked(a);
            }
            return replyOk(out);
        }
        case V_GET_COMPOSITION_DELAY_MAX: return replyInt(out, 1000);
        case V_GET_COMPOSITION_SIZE_MAX: return replyInt(out, 64);
        case V_GET_SUPPORTED_PRIMITIVES: return replyInts(out, supportedPrimitives());
        case V_GET_PRIMITIVE_DURATION: {
            int32_t p = 0;
            binder_status_t r = AParcel_readInt32(in, &p);
            if (r != STATUS_OK) return r;
            if (!primitiveSupported(p)) return replyEx(out, EX_UNSUPPORTED_OPERATION, "primitive");
            return replyInt(out, primitiveMs(p));
        }
        case V_COMPOSE: {
            std::vector<CompositeEffect> effects;
            binder_status_t r = readComposite(in, &effects);
            if (r != STATUS_OK) return r;
            Callback cb = readCallback(in);
            if (effects.empty() || effects.size() > 64) return replyEx(out, EX_ILLEGAL_ARGUMENT, "size");
            for (const auto& e : effects) {
                if (!primitiveSupported(e.primitive)) return replyEx(out, EX_UNSUPPORTED_OPERATION, "primitive");
                if (e.delayMs < 0 || e.delayMs > 1000 || !(e.scale >= 0.0f && e.scale <= 1.0f))
                    return replyEx(out, EX_ILLEGAL_ARGUMENT, "delay/scale");
            }
            submit(*m, composeJob(std::move(effects)), std::move(cb));
            return replyOk(out);
        }
        case V_GET_RESONANT_FREQUENCY: return replyFloat(out, gResonantHz);
        default:
            if (code >= FIRST_CALL_TRANSACTION && code <= LAST_CALL_TRANSACTION)
                return replyEx(out, EX_UNSUPPORTED_OPERATION, "not supported");
            return STATUS_UNKNOWN_TRANSACTION;
    }
}

// ---------------------------------------------------------------- IVibratorManager binder
int32_t managerCaps() {
    return MCAP_SYNC | MCAP_PREPARE_ON | MCAP_PREPARE_PERFORM | MCAP_PREPARE_COMPOSE |
           MCAP_MIXED_TRIGGER_ON | MCAP_MIXED_TRIGGER_PERFORM | MCAP_MIXED_TRIGGER_COMPOSE |
           MCAP_TRIGGER_CALLBACK;
}

void clearPrepared() {
    for (int32_t id : gSyncIds) {
        if (Motor* m = motorById(id)) {
            m->mPrepared = false;
            m->mPendingJob = nullptr;
            m->mPendingCb.reset();
        }
    }
    gSyncIds.clear();
    gSyncPrepared = false;
}

binder_status_t managerTransact(AIBinder*, transaction_code_t code, const AParcel* in, AParcel* out) {
    switch (code) {
        case TX_GET_INTERFACE_VERSION: return replyInt(out, kInterfaceVersion);
        case TX_GET_INTERFACE_HASH: return replyString(out, kInterfaceHash);
        case M_GET_CAPABILITIES: return replyInt(out, managerCaps());
        case M_GET_VIBRATOR_IDS: {
            std::vector<int32_t> ids;
            for (size_t i = 0; i < gMotors.size(); ++i) ids.push_back(static_cast<int32_t>(i));
            return replyInts(out, ids);
        }
        case M_GET_VIBRATOR: {
            int32_t id = 0;
            binder_status_t r = AParcel_readInt32(in, &id);
            if (r != STATUS_OK) return r;
            if (!motorById(id)) return replyEx(out, EX_ILLEGAL_ARGUMENT, "vibrator id");
            r = replyOk(out);
            return r == STATUS_OK ? AParcel_writeStrongBinder(out, gVibratorBinders[id]) : r;
        }
        case M_PREPARE_SYNCED: {
            std::vector<int32_t> ids;
            binder_status_t r = readIntArray(in, &ids);
            if (r != STATUS_OK) return r;
            std::lock_guard<std::mutex> l(gSyncMu);
            if (gSyncPrepared) return replyEx(out, EX_ILLEGAL_STATE, "already prepared");
            for (int32_t id : ids)
                if (!motorById(id)) return replyEx(out, EX_ILLEGAL_ARGUMENT, "vibrator id");
            for (int32_t id : ids) {
                Motor* m = motorById(id);
                m->cancel();
                m->mPendingJob = nullptr;
                m->mPendingCb.reset();
                m->mPrepared = true;
            }
            gSyncIds = ids;
            gSyncPrepared = true;
            return replyOk(out);
        }
        case M_TRIGGER_SYNCED: {
            Callback cb = readCallback(in);
            std::lock_guard<std::mutex> l(gSyncMu);
            if (!gSyncPrepared) return replyEx(out, EX_ILLEGAL_STATE, "not prepared");
            // start every parked job back to back, then report the trigger callback once all
            // of them finished (each job's own callback still fires from its motor thread)
            std::vector<Motor*> started;
            for (int32_t id : gSyncIds) {
                Motor* m = motorById(id);
                m->mPrepared = false;
                if (m->mPendingJob) {
                    m->run(std::move(m->mPendingJob), std::move(m->mPendingCb));
                    m->mPendingJob = nullptr;
                    m->mPendingCb.reset();
                    started.push_back(m);
                }
            }
            gSyncIds.clear();
            gSyncPrepared = false;
            if (cb) {
                std::thread([started, cb]() {
                    std::this_thread::sleep_for(2ms);  // let the motor threads pick up their jobs
                    auto deadline = Clock::now() + 70s;
                    for (Motor* m : started)
                        while (m->mVibrating && Clock::now() < deadline) std::this_thread::sleep_for(2ms);
                    cb.fire();
                }).detach();
            }
            return replyOk(out);
        }
        case M_CANCEL_SYNCED: {
            std::lock_guard<std::mutex> l(gSyncMu);
            clearPrepared();
            return replyOk(out);
        }
        default:
            if (code >= FIRST_CALL_TRANSACTION && code <= LAST_CALL_TRANSACTION)
                return replyEx(out, EX_UNSUPPORTED_OPERATION, "not supported");
            return STATUS_UNKNOWN_TRANSACTION;
    }
}

binder_status_t managerDump(AIBinder*, int fd, const char**, uint32_t) {
    dprintf(fd, "tb321fu-vibrator (AIDL V%d)\n", kInterfaceVersion);
    dprintf(fd, "  resonant frequency: %.1f Hz\n", gResonantHz);
    dprintf(fd, "  gain_max: %d %%, ramps: %d\n", propInt("persist.tb321fu.vibrator.gain_max", 100),
            rampsEnabled() ? 1 : 0);
    for (Motor* m : gMotors)
        dprintf(fd, "  vibrator %d (%s): vibrating=%d prepared=%d amplitude=%.2f\n", m->id(), m->name(),
                m->mVibrating.load(), m->mPrepared.load(), m->mAmplitude);
    return STATUS_OK;
}

// ---------------------------------------------------------------- device discovery
// Two Awinic AW86937 on one i2c bus (the bus number depends on probe order; seen as i2c-3):
//   i2c client "haptic_hv_l" (0x5b) = left, "haptic_hv_r" (0x5a) = right; both input devices are "aw-haptic-hv".
std::string readTrim(const std::string& path) {
    char buf[64] = {};
    int fd = ::open(path.c_str(), O_RDONLY | O_CLOEXEC);
    if (fd < 0) return {};
    ssize_t n = ::read(fd, buf, sizeof(buf) - 1);
    ::close(fd);
    if (n <= 0) return {};
    std::string s(buf, n);
    while (!s.empty() && (s.back() == '\n' || s.back() == ' ')) s.pop_back();
    return s;
}

std::string findEvent(const char* i2cName) {
    for (int attempt = 0; attempt < 20; ++attempt) {  // driver probes in early boot; 2 s is plenty
        DIR* d = opendir("/sys/class/input");
        if (d) {
            while (dirent* e = readdir(d)) {
                if (strncmp(e->d_name, "event", 5) != 0) continue;
                std::string base = std::string("/sys/class/input/") + e->d_name;
                if (readTrim(base + "/device/name") != "aw-haptic-hv") continue;
                if (readTrim(base + "/device/device/name") != i2cName) continue;
                closedir(d);
                return std::string("/dev/input/") + e->d_name;
            }
            closedir(d);
        }
        std::this_thread::sleep_for(100ms);
    }
    return {};
}

// NOTE: do not read /sys/class/leds/vibrator_*/f0 or cali: on haptic_hv those trigger an f0
// measurement that physically drives the motor. DT f0_pre is 0x6a4 = 1700 (0.1 Hz units).
float resonantHz() {
    int v = propInt("persist.tb321fu.vibrator.f0_dhz", 1700);
    return (v > 500 && v < 5000) ? v / 10.0f : 170.0f;
}

}  // namespace

int main() {
    LOGI("starting");
    if (!gPlat.load()) { LOGE("libbinder_ndk platform API missing"); return 1; }

    gCallbackClass = AIBinder_Class_define(
            kCallbackDescriptor, [](void*) -> void* { return nullptr; }, [](void*) {},
            [](AIBinder*, transaction_code_t, const AParcel*, AParcel*) -> binder_status_t {
                return STATUS_UNKNOWN_TRANSACTION;
            });
    gVibratorClass = AIBinder_Class_define(
            kVibratorDescriptor, [](void* args) -> void* { return args; }, [](void*) {}, vibratorTransact);
    gManagerClass = AIBinder_Class_define(
            kManagerDescriptor, [](void* args) -> void* { return args; }, [](void*) {}, managerTransact);
    AIBinder_Class_setOnDump(gManagerClass, managerDump);

    int motors = propInt("persist.tb321fu.vibrator.motors", 3);
    float ceiling = std::clamp(propInt("persist.tb321fu.vibrator.gain_max", 100), 10, 100) / 100.0f;
    struct { const char* i2c; const char* name; int bit; } want[] = {{"haptic_hv_l", "left", 1}, {"haptic_hv_r", "right", 2}};
    for (auto& w : want) {
        if (!(motors & w.bit)) continue;
        std::string dev = findEvent(w.i2c);
        if (dev.empty()) { LOGE("%s motor (%s) not found", w.name, w.i2c); continue; }
        auto* m = new Motor(static_cast<int>(gMotors.size()), w.name, dev);
        m->mGainCeiling = ceiling;
        if (m->open()) gMotors.push_back(m); else delete m;
    }
    gResonantHz = resonantHz();
    LOGI("%zu motor(s), f0 %.1f Hz", gMotors.size(), gResonantHz);

    for (Motor* m : gMotors) gVibratorBinders.push_back(AIBinder_new(gVibratorClass, m));
    AIBinder* manager = AIBinder_new(gManagerClass, nullptr);

    gPlat.setThreadPoolMaxThreadCount(4);
    gPlat.startThreadPool();
    // Registers even with 0 motors: the instance is declared in VINTF, so system_server waits
    // for it; never leave it hanging.
    binder_exception_t ex = gPlat.addService(manager, kInstance);
    if (ex != EX_NONE) { LOGE("addService(%s) failed: %d", kInstance, ex); return 1; }
    LOGI("registered %s", kInstance);
    gPlat.joinThreadPool();
    return 0;
}
