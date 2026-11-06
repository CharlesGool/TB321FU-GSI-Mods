# webview-full:用完整的 Android System WebView APK 换掉 Pixel 镜像里的"占位 + 压缩包"组合,开机不需要再解压。
# Pixel 镜像的 WebView 是 product/app/WebViewGoogle-Stub/(12KB 占位)+ product/app/WebViewGoogle/WebViewGoogle.apk.gz,
# 要靠 PackageManager 首次开机解压到 /data/app。DP11 在本机上没解压出来,WebView 不可用,
# 谷歌账号登录等用到 WebView 的界面一打开就闪退(2026-11-06 user-v1.0 真机)。
# APK 由用户提供(WEBVIEW_APK,见 conf.d/webview.conf),仓库里不放。原生库在 APK 里不压缩、按页对齐(extractNativeLibs=false),
# 系统应用直接从 APK 里加载,不用解出 lib/ 目录。
PKG=com.google.android.webview
need_input WEBVIEW_APK
for t in aapt2 zipalign apksigner unzip; do need_tool "$t"; done
need_file product/app/WebViewGoogle-Stub/WebViewGoogle-Stub.apk

badge=$(aapt2 dump badging "$WEBVIEW_APK" 2>/dev/null)
pkg=$(sed -n "s/^package: name='\([^']*\)'.*versionName='\([^']*\)'.*/\1 \2/p" <<<"$badge")
[[ ${pkg%% *} == "$PKG" ]] || die "WEBVIEW_APK 的包名不是 $PKG:${pkg:-读不出}"
grep -q "^native-code: 'arm64-v8a'" <<<"$badge" || die "WEBVIEW_APK 里没有 arm64-v8a 的原生库"
grep -q 'uses-static-library' <<<"$badge" && die "WEBVIEW_APK 依赖 Trichrome 静态库,要用独立版(standalone)WebView"
# 先存下来再 grep:管道里 grep -q 提前退出会让 aapt2 吃 SIGPIPE,pipefail 下整条判失败
manifest=$(aapt2 dump xmltree --file AndroidManifest.xml "$WEBVIEW_APK" 2>/dev/null || true)
grep -q 'extractNativeLibs.*=false' <<<"$manifest" \
    || die "WEBVIEW_APK 的 extractNativeLibs 不是 false:系统应用不会解压原生库,装进去也加载不了"
zipalign -c -P 16 4 "$WEBVIEW_APK" >/dev/null 2>&1 || die "WEBVIEW_APK 的原生库没有按 16KB 页对齐"

# 签名要和底包里的 WebView 一样(provider 清单按签名认)
stub_cert=$(sudo cat "$SYS/product/app/WebViewGoogle-Stub/WebViewGoogle-Stub.apk" > "$WORK/stub.apk"; apksigner verify --print-certs "$WORK/stub.apk" 2>/dev/null | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')
new_cert=$(apksigner verify --print-certs "$WEBVIEW_APK" 2>/dev/null | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')
[[ -n $new_cert && $new_cert == "$stub_cert" ]] || die "WEBVIEW_APK 的签名($new_cert)和底包 WebView 占位的($stub_cert)不一样"
log "WebView ${pkg#* }(签名和底包一致)"

remove product/app/WebViewGoogle-Stub product/app/WebViewGoogle
log "删了底包的 WebView 占位和压缩包($REMOVED 项)"
put_dir product/app/WebViewGoogle 0755 0:0 u:object_r:system_file:s0
put "$WEBVIEW_APK" product/app/WebViewGoogle/WebViewGoogle.apk 0644 0:0 u:object_r:system_file:s0
log "完成:product/app/WebViewGoogle/WebViewGoogle.apk"
