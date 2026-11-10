# zuicamera/008.predictive-back — 联想相机预测性返回

给 `com.zui.camera` 开预测性返回(Android 13+ 的返回手势/动画)。

## 做什么

只给二进制 `AndroidManifest.xml` 的 `<application>` 加一个属性:

```
android:enableOnBackInvokedCallback="true"   (resid 0x0101066c, 布尔 true)
```

`resources.arsc`、`classes*.dex` 一律不动,再用 overlay key 重签。

## 为什么直接动二进制 AXML,而不是 apktool 整包回编

ZuiCamera 的 `res/values/styles.xml` 引用了私有的 android 属性(`screenLayout`、`headerLayout`、`thumbMinHeight` 等),apktool `b` 走 aapt2 重新链接资源会报 `resource/attribute ... is private` 直接失败。`toolkit/lib/apk-smali.sh` 也因此明确不许改 `AndroidManifest.xml` / `resources.arsc`(它只换 dex)。

所以这里对二进制 AXML 定点下刀(`files/axml_add_predback.py`):

1. 在字符串池 `index = resmap 长度` 处插入属性名字符串 `enableOnBackInvokedCallback`;
2. resmap(属性名→resid 表)在同一 index 追加 `0x0101066c`;
3. 把 XML 区里所有 `>=` 该 index 的字符串引用整体 `+1`(节点名、属性名/值、typed STRING 值、comment 等);
4. 给 `<application>` 起始标签追加该属性(ns=android、typed INT_BOOLEAN=0x12、data=0xffffffff);
5. 重算字符串池 / resmap / `<application>` chunk / 文件头的大小。

幂等:manifest 里已经有这个属性就原样放回,不重复加。

## 验证

- `aapt2 dump xmltree` 对比原包:整棵树**只多** `enableOnBackInvokedCallback=true` 一行,其余元素/属性/资源引用逐字不变。
- 真机(2026-11-10,用户):`adb install -r` 覆盖安装后,相机内返回(面板、模式、设置页)全部正常,预测性返回生效。

## 风险

ZuiCamera 有 4 个 `onKeyDown` 重写。开这个开关后系统不再把返回键发给 `onKeyDown`、改走 `OnBackInvokedDispatcher`;若它的 onKeyDown 里处理了返回会失效。真机实测没有这个问题(返回走的是 `onBackPressed`,框架在开启后仍会兜底调用)。
