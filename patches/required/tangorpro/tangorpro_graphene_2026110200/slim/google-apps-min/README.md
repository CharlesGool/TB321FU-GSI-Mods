# slim/google-apps-min(DP11 / A17 最小精简)

只删用户 2026-11-06 指定的 8 个 Google 应用,其余一律保留。取代旧 cp3a 的大面积精简
(`optional/slim/google-apps` + `optional/slim/accessibility`)。

| 应用 | 目录(相对 system/) |
|---|---|
| 计算器 | product/app/CalculatorGooglePrebuilt_85022643 |
| 日历 | product/app/CalendarGooglePrebuilt |
| 通讯录 | product/app/GoogleContacts |
| 我的 Pixel(com.google.android.apps.tips) | product/priv-app/TipsPrebuilt_v8.7.4.949233121 |
| 信息(Google Messages) | product/priv-app/PrebuiltBugle |
| Kids Space | product/priv-app/KidsHomePrebuilt |
| Play 读书 | product/app/PlayBooksPrebuilt |
| YouTube Kids | product/app/YouTubeKidsPrebuilt |

**必须保留**:数字健康 `product/priv-app/WellbeingPrebuilt`——删了从 Play 装回来功能不正常。

目录名带版本后缀的(Calculator、Tips)以本 DP11 底包实际为准;换底包(新的 DP11/Canary 工厂包)时要重新核对各目录名。
