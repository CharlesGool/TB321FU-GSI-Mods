import com.android.internal.util.HeraldNetSpeedFormat;

public class FormatTest {
    static int fail = 0;
    static void eq(String what, String got, String want) {
        if (!got.equals(want)) { fail++; System.out.println("FAIL " + what + ": 期望 '" + want + "' 实际 '" + got + "'"); }
    }
    public static void main(String[] a) {
        eq("0", HeraldNetSpeedFormat.rate(0, false), "0B/s");
        eq("负数当0", HeraldNetSpeedFormat.rate(-5, false), "0B/s");
        eq("512B", HeraldNetSpeedFormat.rate(512, false), "512B/s");
        eq("1023B", HeraldNetSpeedFormat.rate(1023, false), "1023B/s");
        eq("1KB", HeraldNetSpeedFormat.rate(1024, false), "1.0KB/s");
        eq("1.5KB", HeraldNetSpeedFormat.rate(1536, false), "1.5KB/s");
        eq("12KB", HeraldNetSpeedFormat.rate(12 * 1024 + 300, false), "12KB/s");
        eq("1.2MB", HeraldNetSpeedFormat.rate((long) (1.2 * 1024 * 1024), false), "1.2MB/s");
        eq("123MB", HeraldNetSpeedFormat.rate(123L * 1024 * 1024, false), "123MB/s");
        eq("2GB", HeraldNetSpeedFormat.rate(2L * 1024 * 1024 * 1024, false), "2.0GB/s");
        eq("GB封顶", HeraldNetSpeedFormat.rate(5000L * 1024 * 1024 * 1024, false), "5000GB/s");
        eq("比特 125B=1000b", HeraldNetSpeedFormat.rate(125, true), "1.0Kb/s");
        eq("比特 1MB/s", HeraldNetSpeedFormat.rate(1000000, true), "8.0Mb/s");
        eq("比特 0", HeraldNetSpeedFormat.rate(0, true), "0b/s");
        eq("两行", HeraldNetSpeedFormat.both(2048, 1048576, false), "↑2.0KB/s\n↓1.0MB/s");
        eq("合计带箭头", HeraldNetSpeedFormat.total(1048576, false), "↑↓1.0MB/s");
        eq("最宽", HeraldNetSpeedFormat.widest(false), "↓1023KB/s");
        if (fail == 0) System.out.println("通过");
        System.exit(fail == 0 ? 0 : 1);
    }
}
