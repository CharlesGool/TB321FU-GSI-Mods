# 删 /system/phh 里各厂商的按键布局、NFC 配置和子目录,但保留 phh/empty。
# rw-system.sh 无条件地把 phh/empty 盖到 vendor 的 libpdx_default_transport.so 上(没有 || true、没有机型判断),
# 删掉它会让这个 vendor 库不再被盖住,行为和以前不一样,所以留着。
need_file phh/empty
n=0
while IFS= read -r p; do
    [[ $p == empty ]] && continue
    remove "phh/$p"; n=$((n + REMOVED))
done < <(sudo ls -A "$SYS/phh")
log "删了 $n 项,phh/empty 保留"
