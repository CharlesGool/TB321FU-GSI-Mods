# bootanim-portrait:把 Pixel Tablet 横屏尺寸(2560x1600)的开机动画转成 TB321FU 面板的竖屏尺寸(1600x2560)。
# 现取底包的 product/media/bootanimation.zip → rotate_bootanim.py(desc 宽高对调、每帧转 90°、trim 框换算)→ zipalign → 换回。
# 方向 BOOTANIM_ROTATE=cw(默认)|ccw:cw = 平板逆时针横过来(系统横屏 ROTATION_90,见 rotation-fix)时画面正立。
need_tool zipalign
need_file product/media/bootanimation.zip
ROT=${BOOTANIM_ROTATE:-cw}
[[ $ROT == cw || $ROT == ccw ]] || die "BOOTANIM_ROTATE 只能是 cw 或 ccw,现在是 '$ROT'"
sudo cat "$SYS/product/media/bootanimation.zip" > "$WORK/ba.orig.zip"
rc=0; python3 -I "$MOD/rotate_bootanim.py" "$WORK/ba.orig.zip" "$WORK/ba.rot.zip" "$ROT" > "$WORK/rot.log" 2>&1 || rc=$?
sed 's/^/    /' "$WORK/rot.log"
if [[ $rc == 3 ]]; then log "开机动画本来就是竖屏尺寸,不改"; return 0; fi
[[ $rc == 0 ]] || die "转开机动画失败"
zipalign -f 4 "$WORK/ba.rot.zip" "$WORK/bootanimation.zip" || die "zipalign 失败"
python3 -I - "$WORK/bootanimation.zip" <<'PY' || die "产物 zip 校验失败(有压缩条目或 desc 不是竖屏)"
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1]); assert z.testzip() is None
assert all(i.compress_type == zipfile.ZIP_STORED for i in z.infolist())
w, h = map(int, z.read('desc.txt').split()[:2]); assert w < h
PY
replace "$WORK/bootanimation.zip" product/media/bootanimation.zip
log "开机动画已转竖屏($ROT):$(sha256sum "$WORK/bootanimation.zip" | cut -c1-16)"
