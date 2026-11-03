#!/usr/bin/env python3
"""生成和新 system 镜像配套的 vbmeta_system.img。

用法: mk_vbmeta_system.py <原厂 vbmeta_system.img> <新 system.img(带 AVB footer)> <输出> <签名私钥.pem> [avbtool.py 路径]

做法:读原厂 vbmeta_system 的全部 descriptor(pvmfw 的 hash、product/system_ext 的 hashtree、build 属性),
原样保留;只把 system 的 hashtree descriptor 换成新 system.img 自己 AVB footer 里那份(avbtool 签名时已经算好
image_size/tree_offset/salt/root_digest,直接复用)。rollback_index、flags、算法都沿用原厂,用给定私钥重签。
前提:product/system_ext 这两个逻辑分区没动(沿用原厂)。动了就要用同样方法把它们的 descriptor 也换掉。
"""
import os
import sys

here = os.path.dirname(os.path.abspath(__file__))
avb_path = sys.argv[5] if len(sys.argv) > 5 else os.path.join(here, "avbtool.py")
sys.path.insert(0, os.path.dirname(os.path.abspath(avb_path)))
import avbtool  # noqa: E402

orig_path, sys_path, out_path, key = sys.argv[1:5]


def descriptors(blob):
    h = avbtool.AvbVBMetaHeader(blob[:avbtool.AvbVBMetaHeader.SIZE])
    start = avbtool.AvbVBMetaHeader.SIZE + h.authentication_data_block_size + h.descriptors_offset
    return h, avbtool.parse_descriptors(blob[start:start + h.descriptors_size])


with open(orig_path, "rb") as f:
    orig_h, orig_d = descriptors(f.read())
with open(sys_path, "rb") as f:
    f.seek(-avbtool.AvbFooter.SIZE, 2)
    footer = avbtool.AvbFooter(f.read(avbtool.AvbFooter.SIZE))
    f.seek(footer.vbmeta_offset)
    _, sys_d = descriptors(f.read(footer.vbmeta_size))

new_sys = next((d for d in sys_d if isinstance(d, avbtool.AvbHashtreeDescriptor) and d.partition_name == "system"), None)
if new_sys is None:
    sys.exit("新 system.img 的 AVB footer 里没有 system hashtree descriptor")
out_d, swapped = [], False
for d in orig_d:
    if isinstance(d, avbtool.AvbHashtreeDescriptor) and d.partition_name == "system":
        out_d.append(new_sys); swapped = True
        print(f"  system: root_digest {d.root_digest.hex()[:16]}… -> {new_sys.root_digest.hex()[:16]}…")
    else:
        out_d.append(d)
if not swapped:
    sys.exit("原厂 vbmeta_system 里没有 system hashtree descriptor,不能用这个方法")

alg = avbtool.lookup_algorithm_by_type(orig_h.algorithm_type)[0]
blob = avbtool.Avb()._generate_vbmeta_blob(
    algorithm_name=alg, key_path=key, public_key_metadata_path=None, descriptors=out_d,
    chain_partitions_use_ab=None, chain_partitions_do_not_use_ab=None,
    rollback_index=orig_h.rollback_index, flags=orig_h.flags,
    rollback_index_location=orig_h.rollback_index_location,
    props=None, props_from_file=None, kernel_cmdlines=None, setup_rootfs_from_kernel=None,
    ht_desc_to_setup=None, include_descriptors_from_image=None, signing_helper=None,
    signing_helper_with_files=None, release_string=None, append_to_release_string=None,
    required_libavb_version_minor=orig_h.required_libavb_version_minor)
blob += b"\0" * ((4096 - len(blob) % 4096) % 4096)
with open(out_path, "wb") as f:
    f.write(blob)
print(f"  写出 {out_path}({len(blob)} 字节,{alg},rollback_index={orig_h.rollback_index},flags={orig_h.flags})")
