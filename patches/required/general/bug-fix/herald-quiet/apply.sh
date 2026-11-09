# herald-quiet:把 herald_quiet.cil 追加到 plat_sepolicy.cil(herald-core 那段之后)。只加 dontaudit,不改放行。
require_mod required/general/herald-core
cil_append "herald-quiet: herald 域不记 avc" "$MOD/herald_quiet.cil"
