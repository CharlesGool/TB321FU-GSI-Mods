# GSI 下 product/system_ext 是 system 里的目录,没有单独的 dm-verity,partition.*.verified 读出来是 0。
# build.prop 写 1 对 product/system_ext 生效;system/vendor/odm 三个在 init 挂分区时就被设成 0(早于 build.prop),
# 所以再用 post-fs-data 的 rc 覆盖一次。
append build.prop <<'PROP'

# gsi-hide/partition-verified: GSI 下这几个 verity 状态位默认是 0,改成和原厂一致
partition.system.verified=1
partition.vendor.verified=1
partition.odm.verified=1
partition.product.verified=1
partition.system_ext.verified=1
PROP
put "$MOD/files/init.hardenpartverified.rc" etc/init/init.hardenpartverified.rc 0644 0:0 u:object_r:system_file:s0
