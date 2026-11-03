# overlay-idmap-reset:开机最早阶段删掉我们自己 overlay 的旧 idmap 缓存,原理见本目录 README.md。
need_file etc/selinux/plat_sepolicy.cil
LIST=$MOD/files/overlays.txt
[[ -f $LIST ]] || die "缺 $LIST"
RC=$WORK/tb321fu-idmap-reset.rc
{
  echo "# 由 patches/optional/overlay-idmap-reset 生成。idmap2d 读到损坏的旧 idmap 会崩(V69/V70 的 brightness-curve),"
  echo "# 所以在 zygote / system_server 起来之前把我们自己 overlay 的 idmap 删掉,让 OverlayManager 开机时重新生成。"
  echo "on post-fs-data"
  while IFS= read -r n; do
      [[ -z $n || $n == \#* ]] && continue
      echo "    rm /data/resource-cache/system@product@overlay@$n.apk@idmap"
  done < "$LIST"
} > "$RC"
put "$RC" etc/init/tb321fu-idmap-reset.rc 0644 0:0 u:object_r:system_file:s0
cil_append "overlay-idmap-reset: init 删旧 idmap" "$MOD/tb321fu-idmap.cil"
