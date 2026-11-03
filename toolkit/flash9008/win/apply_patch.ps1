# TB321FU patch 应用脚本: 把补丁包解压到刷机目录根 (和 flash_select.bat 同级) 后运行,
# 生成 flash_auto.ps1 需要的全部文件, 之后用 flash_select.bat 刷入。
# 用法: apply_patch.bat                应用 patch\ 下最新版本
#       apply_patch.bat 60             应用 V60
#       apply_patch.bat 60 -Base D:\x\super_4_v49.img   基准镜像不在 image\ 下时指定路径
#       apply_patch.bat 60 -Force      已生成过也重新生成
param(
    [string]$Version = '',
    [string]$Base = '',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$root = $PSScriptRoot
$img  = Join-Path $root 'image'
$pdir = Join-Path $root 'patch'

function Info([string]$m) { Write-Host "[信息] $m" -ForegroundColor Cyan }
function Ok([string]$m)   { Write-Host "[完成] $m" -ForegroundColor Green }
function Warn([string]$m) { Write-Host "[注意] $m" -ForegroundColor Yellow }
function Fail([string]$m) { Write-Host ''; Write-Host "[失败] $m" -ForegroundColor Red; exit 1 }
function Get-Sha([string]$p) { (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLower() }

Write-Host '============================================================'
Write-Host '  TB321FU patch 应用 (生成 flash_auto 所需文件, 不刷机)'
Write-Host '============================================================'

# ---- 1. 选版本 ----
$avail = @()
if (Test-Path -LiteralPath $pdir) {
    $avail = @(Get-ChildItem -Path $pdir -Directory | ForEach-Object {
        if ($_.Name -match '^V(\d+)$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'manifest.json'))) { [int]$Matches[1] }
    } | Sort-Object)
}
if ($avail.Count -eq 0) { Fail 'patch\ 下没有任何 Vxx\manifest.json, 请确认补丁包解压到了刷机目录根。' }
if ($Version) {
    $digits = $Version -replace '[^\d]', ''
    if (-not $digits) { Fail "版本参数 '$Version' 不是数字。" }
    $n = [int]$digits
    if ($avail -notcontains $n) { Fail ("patch\ 下没有 V{0}。可用: {1}" -f $n, (($avail | ForEach-Object { "V$_" }) -join ', ')) }
} else {
    $n = $avail[-1]
    Info ("未指定版本, 自动选最新: V{0}" -f $n)
}
$pv = Join-Path $pdir "V$n"
$m = Get-Content -LiteralPath (Join-Path $pv 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$m.version -ne $n) { Fail "manifest.json 里的版本 ($($m.version)) 和目录 V$n 对不上。" }
$b = [int]$m.base
Info "目标: V$n  (基准: V$b)  $($m.note)"

# ---- 2. 补丁包自带文件是否到位 ----
$bad = @()
foreach ($p in $m.files.PSObject.Properties) {
    $f = Join-Path $root ($p.Name -replace '/', '\')
    if (-not (Test-Path -LiteralPath $f)) { $bad += "缺少: $($p.Name)"; continue }
    if ((Get-Sha $f) -ne $p.Value) { $bad += "校验不符: $($p.Name)" }
}
if ($bad.Count -gt 0) { $bad | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }; Fail '补丁包文件不全或已损坏, 请重新解压。' }
Ok '补丁包自带文件齐全 (super_1 / rawprogram / vbmeta_system)'

# ---- 3. 还原 super_4 (system 本体) ----
$out = Join-Path $img "super_4_v$n.img"
if ((Test-Path -LiteralPath $out) -and -not $Force -and ((Get-Sha $out) -eq $m.super_4_sha256)) {
    Ok "super_4_v$n.img 已存在且校验通过, 跳过还原"
} else {
    $xd = @((Join-Path $root 'tool\xdelta3.exe'), (Join-Path $root 'xdelta3.exe')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $xd) { $c = Get-Command xdelta3 -ErrorAction SilentlyContinue; if ($c) { $xd = $c.Source } }
    if (-not $xd) { Fail '找不到 xdelta3.exe (应在 tool\ 下, 补丁包里自带)。' }

    if (-not $Base) { $Base = Join-Path $img "super_4_v$b.img" }
    if (-not (Test-Path -LiteralPath $Base)) {
        Fail ("找不到基准镜像: {0}`n  这个补丁基于 V{1} 的 super_4_v{1}.img; 文件在别处请用 -Base 指定。" -f $Base, $b)
    }
    Info "校验基准镜像 (约 10 秒)..."
    if ((Get-Sha $Base) -ne $m.base_sha256) { Fail "基准镜像 sha256 不符, 不是构建侧用的 V$b。别用它还原。" }

    $tmp = "$out.tmp"
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    Info '还原 system 镜像 (xdelta3)...'
    & $xd -d -f -s $Base (Join-Path $pv $m.patch) $tmp
    if ($LASTEXITCODE -ne 0) { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }; Fail "xdelta3 解码失败 (exit $LASTEXITCODE)。" }
    if ((Get-Sha $tmp) -ne $m.super_4_sha256) { Remove-Item -LiteralPath $tmp -Force; Fail '还原结果 sha256 不符, 已丢弃, 别刷。' }
    Move-Item -LiteralPath $tmp -Destination $out -Force
    Ok "已生成 image\super_4_v$n.img (sha256 校验通过)"
}

# ---- 4. 凑齐 V$n 目录里的 boot/init_boot/vendor_boot/vbmeta ----
$vdir = Join-Path $img "V$n"
New-Item -ItemType Directory -Force -Path $vdir | Out-Null
$others = @(Get-ChildItem -Path $img -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^V(\d+)$' -and $_.FullName -ne $vdir } |
    Sort-Object { [int]($_.Name -replace '[^\d]', '') } -Descending)
foreach ($p in $m.boot_set.PSObject.Properties) {
    $dst = Join-Path $vdir $p.Name
    if (Test-Path -LiteralPath $dst) {
        if ((Get-Sha $dst) -ne $p.Value) { Warn ("V$n\{0} 已存在但 sha256 和构建侧不同, 保留现有文件。" -f $p.Name) }
        continue
    }
    $src = $null
    foreach ($o in $others) {
        $c = Join-Path $o.FullName $p.Name
        if ((Test-Path -LiteralPath $c) -and ((Get-Sha $c) -eq $p.Value)) { $src = $c; break }
    }
    if (-not $src) {
        foreach ($o in $others) {
            $c = Join-Path $o.FullName $p.Name
            if (Test-Path -LiteralPath $c) { $src = $c; Warn ("{0}: 没找到 sha256 一致的, 退而用 {1} 里的同名文件。" -f $p.Name, $o.Name); break }
        }
    }
    if (-not $src) { Fail ("V$n\{0} 缺失, 其它 Vxx 目录里也没有同名文件。" -f $p.Name) }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Info ("已从 {0} 复制 {1}" -f (Split-Path (Split-Path $src) -Leaf), $p.Name)
}
Ok "image\V$n 里 boot/init_boot/vendor_boot/vbmeta/vbmeta_system 齐全"

# ---- 5. 和 flash_auto 的必需文件清单对一遍 ----
$need = @("super_1_v$n.img", "super_4_v$n.img", "rawprogram_save_persist_unsparse0_v$n.xml") | ForEach-Object { Join-Path $img $_ }
$need += @('boot.img', 'init_boot.img', 'vendor_boot.img', 'vbmeta.img', 'vbmeta_system.img') | ForEach-Object { Join-Path $vdir $_ }
$missing = @($need | Where-Object { -not (Test-Path -LiteralPath $_) })
if ($missing.Count -gt 0) { $missing | ForEach-Object { Write-Host "  缺少: $_" -ForegroundColor Red }; Fail '版本专属文件仍不全。' }

Write-Host ''
Ok "V$n 已就绪, 运行 flash_select.bat 刷入即可 (不清 data)。"
Write-Host ''
Write-Host '如需在选择菜单里显示备注, 把下面这一行加到 flash_select.ps1 的 $notes 里:' -ForegroundColor DarkGray
Write-Host ("    {0} = '{1}'" -f $n, ($m.note -replace "'", "''"))
exit 0
