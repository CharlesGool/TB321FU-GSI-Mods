# 蓝牙属性:关 A2DP 硬件 offload、关 LE Audio 相关 profile。写进 product/etc/build.prop(product 最后加载,能盖住 vendor 的值)。
need_file product/etc/build.prop
[[ -f $MOD/bt.prop ]] || die "缺 $MOD/bt.prop"
# 已有的 key 就地改,没有的追加到末尾
edit product/etc/build.prop python3 -I "$MOD/props.py" "$MOD/bt.prop"
