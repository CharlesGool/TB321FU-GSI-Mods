# backup — 备份

| 模块 | 做什么 | 形式 |
|---|---|---|
| [app-backup](../../patches/optional/app-backup/) | `heraldctl backup …`:把单个应用的 apk(含 split)和数据备份到指定目录,或还原 | 免 root 核心插件 + 后台脚本,依赖 `herald-core` |
