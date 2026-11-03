"""改 boot 的补丁(patches/required/general/boot-kernel/boot-assemble)和 avb_resign 共用的 AVB 读写小工具,和 avbtool.py 放在一起。

只做三件事:
  - load(path):读一个镜像的 vbmeta(独立 vbmeta 镜像,或带 AVB footer 的分区镜像都行)
  - sign(...):按给定 header 参数和 descriptor 列表重新生成并签名 vbmeta blob
  - pubkey(key.pem):算私钥对应的 AVB 公钥(用来核对"重签用的 key 和原来那把是不是同一把")
"""
import hashlib
import os
import sys


def import_avbtool(path=None):
    if path is None:
        here = os.path.dirname(os.path.abspath(__file__))
        path = os.path.join(here, 'avbtool.py')
    path = os.path.abspath(path)
    if not os.path.isfile(path):
        sys.exit(f'找不到 avbtool.py: {path}')
    sys.path.insert(0, os.path.dirname(path))
    import avbtool  # noqa: E402
    return avbtool


class Vbmeta:
    """一个 vbmeta blob 的解析结果。

    footer   有 AVB footer 时是 AvbFooter,否则 None
    header   AvbVBMetaHeader
    blob     vbmeta blob 本体(header + auth + aux,不含尾部补零)
    descs    descriptor 对象列表(按原顺序)
    pub      内嵌公钥(AVB 格式)
    """

    def __init__(self, avb, path):
        self.path = path
        with open(path, 'rb') as f:
            data_end = f.seek(0, 2)
            self.footer = None
            if data_end >= avb.AvbFooter.SIZE:
                f.seek(data_end - avb.AvbFooter.SIZE)
                try:
                    self.footer = avb.AvbFooter(f.read(avb.AvbFooter.SIZE))
                except (LookupError, Exception):  # 没有 footer
                    self.footer = None
            off = self.footer.vbmeta_offset if self.footer else 0
            f.seek(off)
            hb = f.read(avb.AvbVBMetaHeader.SIZE)
            h = avb.AvbVBMetaHeader(hb)
            total = avb.AvbVBMetaHeader.SIZE + h.authentication_data_block_size + h.auxiliary_data_block_size
            f.seek(off)
            self.blob = f.read(total)
        self.header = h
        self.file_size = data_end
        aux = avb.AvbVBMetaHeader.SIZE + h.authentication_data_block_size
        d0 = aux + h.descriptors_offset
        self.descs = avb.parse_descriptors(self.blob[d0:d0 + h.descriptors_size])
        self.pub = self.blob[aux + h.public_key_offset: aux + h.public_key_offset + h.public_key_size]
        self.pkmd_size = h.public_key_metadata_size
        self.alg_name = avb.lookup_algorithm_by_type(h.algorithm_type)[0]
        self.signature_ok = avb.verify_vbmeta_signature(h, self.blob)


def load(avb, path):
    return Vbmeta(avb, path)


def sha1(b):
    return hashlib.sha1(b).hexdigest()


def pubkey(avb, key_path):
    return avb.RSAPublicKey(key_path).encode()


def sign(avb, like, descs, key_path):
    """用 like(一个 Vbmeta)的 header 参数,对 descs 重新生成 vbmeta blob 并签名。

    沿用:算法、rollback_index、rollback_index_location、flags、release string、
    required_libavb_version_minor。public key metadata 不支持(原镜像带了就让调用方先报错)。
    """
    h = like.header
    if like.pkmd_size:
        raise SystemExit(f'{like.path} 带 public key metadata,这里不支持')
    return avb.Avb()._generate_vbmeta_blob(
        algorithm_name=like.alg_name, key_path=key_path, public_key_metadata_path=None,
        descriptors=list(descs), chain_partitions_use_ab=None, chain_partitions_do_not_use_ab=None,
        rollback_index=h.rollback_index, flags=h.flags, rollback_index_location=h.rollback_index_location,
        props=None, props_from_file=None, kernel_cmdlines=None, setup_rootfs_from_kernel=None,
        ht_desc_to_setup=None, include_descriptors_from_image=None, signing_helper=None,
        signing_helper_with_files=None, release_string=h.release_string, append_to_release_string=None,
        required_libavb_version_minor=h.required_libavb_version_minor)


def same_header_params(a, b):
    """返回两个 Vbmeta 在"该沿用的 header 参数"上的差异列表(空 = 一致)。"""
    out = []
    for f in ('algorithm_type', 'rollback_index', 'rollback_index_location', 'flags',
              'release_string', 'required_libavb_version_major', 'required_libavb_version_minor'):
        va, vb = getattr(a.header, f), getattr(b.header, f)
        if va != vb:
            out.append(f'{f}: {va} -> {vb}')
    return out


def desc_name(d):
    n = type(d).__name__.replace('Avb', '').replace('Descriptor', '')
    return f"{n}({getattr(d, 'partition_name', getattr(d, 'key', ''))})"


def hash_of(avb, path, salt, size, alg='sha256'):
    """AVB hash descriptor 的摘要:H(salt || image[:size])。"""
    h = hashlib.new(alg, salt)
    with open(path, 'rb') as f:
        left = size
        while left:
            c = f.read(min(left, 16 << 20))
            if not c:
                raise SystemExit(f'{path} 不足 {size} 字节')
            h.update(c)
            left -= len(c)
    return h.digest()
