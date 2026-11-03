#!/usr/bin/env bash
# smooth-display 的 smali 钩子(apply_hook.py):在合成的 smali 上测命中、幂等、锚点缺失时失败、常量正确。
set -uo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
H=$REPO/patches/optional/smooth-display/apply_hook.py
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "失败: $1"; fi; }
F=$T/smali/com/android/server/display/mode/DisplayModeDirector\$SettingsObserver.smali
mkdir -p "$(dirname "$F")"
cat > "$F" <<'SM'
.class public Lx;
.method public final updateRefreshRateSettingLocked(I)V
    .registers 8

    .line 1172
    :goto_0
    iget v0, p0, Lcom/android/server/display/mode/DisplayModeDirector$SettingsObserver;->mDefaultRefreshRate:F

    invoke-virtual {p0, v2, v1, v0, p1}, Lcom/android/server/display/mode/DisplayModeDirector$SettingsObserver;->updateRefreshRateSettingLocked(FFFI)V

    return-void
.end method
SM
python3 -I "$H" "$T" >"$T/o1" 2>&1; ok "命中一处" 'grep -q "已打钩子" "$T/o1"'
ok "60 和 120 的常量" 'grep -q "0x42700000" "$F" && grep -q "const/high16 v1, 0x42f00000    # 120.0f" "$F"'
ok "钩子在 iget 之前、:goto_0 之后" '[[ $(grep -n "goto_0" "$F" | cut -d: -f1) -lt $(grep -n "herald-smooth-display" "$F" | cut -d: -f1) && $(grep -n "herald-smooth-display" "$F" | cut -d: -f1) -lt $(grep -n "mDefaultRefreshRate" "$F" | cut -d: -f1) ]]'
cp "$F" "$T/once"; python3 -I "$H" "$T" >"$T/o2" 2>&1
ok "幂等" 'cmp -s "$F" "$T/once" && grep -q "跳过" "$T/o2"'
python3 -I "$H" "$T" 90 >/dev/null 2>&1; ok "已打过再换 Hz 也不重复打" 'cmp -s "$F" "$T/once"'
rm -f "$F"; mkdir -p "$(dirname "$F")"; printf '.class public Lx;\n.method public final updateRefreshRateSettingLocked(I)V\n    return-void\n.end method\n' > "$F"
python3 -I "$H" "$T" >"$T/o3" 2>&1; rc=$?; ok "锚点缺失时失败" '[[ $rc == 1 ]] && grep -q FAIL "$T/o3"'
echo "通过 $pass,失败 $fail"; (( fail == 0 ))
