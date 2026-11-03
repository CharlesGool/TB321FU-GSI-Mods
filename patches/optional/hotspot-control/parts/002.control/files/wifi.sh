# hotspot-control/002.control 的 broker 插件(装在 /system/etc/herald_payload/plugins/wifi.sh)。
# Wi-Fi 热点覆盖项(Settings.Global 里的 herald_6g_* / herald_ap_* / herald_wifi_country,由 Wi-Fi 服务的 smali 补丁读取)
# 的读写、热点开关(root 才能用 cmd wifi start-softap/stop-softap)、系统热点设置读取。
# 这些代码原来在 herald-start.sh 里(V61–V74),拆出来时一行没改,只换了接入方式。
# V68:读系统「热点」设置(WifiConfigStoreSoftAp.xml,在 wifi 模块私有目录里,只有 root 读得到),
# 每行 键=值,给 wifi_get 附在回复末尾。读不到的某一项整行省略;整个文件读不到时输出一行 `err wifi_sys 原因`。
# 只读,不改任何设置。字段名见 patches/required/general/herald-core/README.md「系统热点配置」。
herald_sx_raw() {   # $1 属性名 → <int|boolean|long name="X" value="V" /> 的 V(只取第一个)
  grep -m1 "name=\"$1\"" "$W/herald_sx" 2>/dev/null | sed -n 's/.*value="\([^"]*\)".*/\1/p'
}
herald_sx_text() {  # $1 属性名 → <string name="X">文本</string> 的文本(还原 XML 转义)
  grep -m1 "name=\"$1\"" "$W/herald_sx" 2>/dev/null | sed -n "s#.*name=\"$1\"[^>]*>\(.*\)</string>.*#\1#p" \
    | sed -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&quot;/"/g' -e "s/&apos;/'/g" -e 's/&amp;/\&/g'
}
herald_sx_bool() {  # $1 属性名 → 0/1,没有就什么都不输出
  case "$(herald_sx_raw "$1")" in true) echo 1 ;; false) echo 0 ;; esac
}
herald_sx_hex2str() {  # 偶数位十六进制 → 字符串(只用 sh 内建的 printf)
  _hx=$1; _out=""
  while [ -n "$_hx" ]; do
    _bb=${_hx%"${_hx#??}"}; _hx=${_hx#??}
    _out="$_out\\$(printf '%03o' "$((0x$_bb))")"
  done
  printf "$_out"
}
herald_wifi_sysconf_body() {
  _sf=""
  for _sd in /data/misc/apexdata/com.android.wifi /data/misc/apexdata/com.google.android.wifi /data/misc/apexdata/*wifi* /data/misc/wifi; do
    [ -f "$_sd/WifiConfigStoreSoftAp.xml" ] && { _sf="$_sd/WifiConfigStoreSoftAp.xml"; break; }
  done
  if [ -z "$_sf" ]; then echo "err wifi_sys 找不到 WifiConfigStoreSoftAp.xml(热点还没保存过配置?)"; return 0; fi
  cat "$_sf" > "$W/herald_sx" 2>"$W/herald_t1" </dev/null
  if [ ! -s "$W/herald_sx" ]; then echo "err wifi_sys 读不了 $_sf: $(head -c 120 "$W/herald_t1" 2>/dev/null | tr '\n' ' ')"; rm -f "$W/herald_sx" "$W/herald_t1"; return 0; fi
  # 名称:新版 WifiSsid(加引号的文本,或不带引号的十六进制);旧版 SSID(明文)
  _v=$(herald_sx_text WifiSsid)
  if [ -n "$_v" ]; then
    case "$_v" in
      \"*\") _v=${_v#\"}; _v=${_v%\"} ;;
      *[!0-9a-fA-F]*) ;;
      *) [ $(( ${#_v} % 2 )) -eq 0 ] && _v=$(herald_sx_hex2str "$_v") ;;
    esac
  else _v=$(herald_sx_text SSID); fi
  [ -n "$_v" ] && echo "sys_ssid=$_v"
  _v=$(herald_sx_text Passphrase); [ -n "$_v" ] && echo "sys_pass=$_v"
  _v=$(herald_sx_raw SecurityType); case "$_v" in [0-3]) echo "sys_sec=$_v" ;; esac
  # 频段:新版每个频段一条 <int name="Band">(位掩码相加);旧版只有一个 ApBand
  _b=0; _nb=0
  for _v in $(grep 'name="Band"' "$W/herald_sx" 2>/dev/null | sed -n 's/.*value="\([0-9]*\)".*/\1/p'); do _b=$(( _b | _v )); _nb=1; done
  [ "$_nb" = 0 ] && { _v=$(herald_sx_raw ApBand); case "$_v" in [0-9]|[0-9][0-9]) _b=$_v; _nb=1 ;; esac; }
  _b=$(( _b & 7 )); [ "$_nb" = 1 ] && [ "$_b" -gt 0 ] && echo "sys_band=$_b"
  _v=$(herald_sx_bool HiddenSSID); [ -n "$_v" ] && echo "sys_hidden=$_v"
  _v=$(herald_sx_raw MaxNumberOfClients); case "$_v" in ""|*[!0-9]*) ;; *) echo "sys_maxclients=$_v" ;; esac
  _v=$(herald_sx_bool AutoShutdownEnabled); [ -n "$_v" ] && echo "sys_autoshut=$_v"
  _v=$(herald_sx_raw ShutdownTimeoutMillis); case "$_v" in ""|*[!0-9]*) ;; *) echo "sys_timeout_min=$(( _v / 60000 ))" ;; esac
  _v=$(herald_sx_bool ClientControlByUser); [ -n "$_v" ] && echo "sys_clientctl=$_v"
  _v=$(herald_sx_raw MacRandomizationSetting); case "$_v" in [0-2]) echo "sys_macrand=$_v" ;; esac
  rm -f "$W/herald_sx" "$W/herald_t1"
  return 0
}
herald_wifi_sysconf() {
  _so=$(herald_wifi_sysconf_body)
  case "$_so" in
    "") echo "err wifi_sys 文件在但一个字段也没解析出来(格式和预期不同)" ;;
    *) printf '%s\n' "$_so" ;;
  esac
}
# Wi-Fi 覆盖项取值校验(用核心的 herald_int_in):合法返回 0;不合法时输出原因并返回 1
herald_wifi_valid() {
  case "$1" in
    herald_6g_channel) herald_int_in "$2" 1 233 && [ $(( ($2 - 1) % 4 )) -eq 0 ] || { echo "6GHz 信道要在 1-233 且 (信道-1) 能被 4 整除,如 5/21/37/53/69/85"; return 1; } ;;
    herald_6g_bw)      case "$2" in -1|2|3|4|6|11) ;; *) echo "只能是 -1/2/3/4/6/11"; return 1 ;; esac ;;
    herald_6g_be|herald_ap_hidden|herald_ap_autoshut|herald_ap_clientctl)
                    case "$2" in 0|1) ;; *) echo "只能是 0 或 1"; return 1 ;; esac ;;
    herald_wifi_country) case "$2" in NONE|[A-Za-z][A-Za-z]) ;; *) echo "两位国家码或 NONE"; return 1 ;; esac ;;
    herald_ap_ssid)    _n=$(printf '%s' "$2" | wc -c); [ "$_n" -le 32 ] || { echo "超过 32 字节"; return 1; } ;;
    herald_ap_pass)    [ ${#2} -ge 8 ] && [ ${#2} -le 63 ] || { echo "长度要 8-63"; return 1; } ;;
    herald_ap_sec)     herald_int_in "$2" 0 3 || { echo "只能是 0-3"; return 1; } ;;
    herald_ap_band)    herald_int_in "$2" 1 7 || { echo "只能是 1-7(1=2.4G 2=5G 4=6G,可相加)"; return 1; } ;;
    herald_ap_bw)      case "$2" in 2|3|4|6) ;; *) echo "只能是 2/3/4/6(20/40/80/160MHz)"; return 1 ;; esac ;;
    herald_ap_macrand) herald_int_in "$2" 0 2 || { echo "只能是 0-2"; return 1; } ;;
    herald_ap_maxclients) herald_int_in "$2" 0 999 || { echo "只能是 0-999"; return 1; } ;;
    herald_ap_timeout_min) herald_int_in "$2" 1 9999 || { echo "只能是 1-9999"; return 1; } ;;
  esac
  return 0
}
# root 执行 `cmd wifi <子命令>`(热点开关这类 shell uid 2000 被拒的命令)。输出同样走文件,不经管道。
herald_wifi_cmd() {
  ( unset LD_LIBRARY_PATH; /system/bin/cmd wifi "$@" >"$W/herald_t4" 2>&1 </dev/null ); _wrc=$?
  if [ "$_wrc" = 0 ] && ! grep -qi 'exception\|failed transaction\|does not have access' "$W/herald_t4"; then
    echo "ok wifi $1"; else echo "err wifi $1 rc=$_wrc"; fi
  head -c 3000 "$W/herald_t4" 2>/dev/null
  rm -f "$W/herald_t4"
}
# V64:热点开关只回一行结果(cmd wifi 会附带大段 SoftAp 回调日志);失败时才附原文最后 40 行
herald_wifi_short() {
  if grep -q 'SAP failed to start' "$W/herald_t6"; then
    echo "err wifi $(head -1 "$W/herald_t6" | cut -d' ' -f3) SAP failed to start"; tail -40 "$W/herald_t6"
  else
    case "$(head -1 "$W/herald_t6")" in
      ok*) head -1 "$W/herald_t6"; grep -m1 -o 'SAP is [a-z ]*' "$W/herald_t6" ;;
      *)   tail -40 "$W/herald_t6" ;;
    esac
  fi
  rm -f "$W/herald_t6"
}
# V73:hotspot_start_system —— 用系统「热点」设置里保存的名称/密码/安全类型/频段起热点,前端不用自己拼参数。
#   做法:读 WifiConfigStoreSoftAp.xml(同 wifi_get 的 sys_* 行),再调 cmd wifi start-softap。
#   start-softap 只接受名称/安全类型/密码/单个频段;隐藏名称、最大连接数等其余设置由我们的热点覆盖项补丁(herald_ap_*)和系统自己决定。
#   频段位掩码含多个频段(如 2.4+5)时传 any。读不到设置、开放热点以外缺密码时报 err,不去猜。
herald_hotspot_start_system() {
  _ss=$(herald_wifi_sysconf_body)
  case "$_ss" in "err wifi_sys"*|"") echo "err hotspot_start_system 读不到系统热点设置: ${_ss:-空}"; return 1 ;; esac
  _n=$(printf '%s\n' "$_ss" | sed -n 's/^sys_ssid=//p' | head -1)
  _p=$(printf '%s\n' "$_ss" | sed -n 's/^sys_pass=//p' | head -1)
  _c=$(printf '%s\n' "$_ss" | sed -n 's/^sys_sec=//p' | head -1)
  _b=$(printf '%s\n' "$_ss" | sed -n 's/^sys_band=//p' | head -1)
  [ -n "$_n" ] || { echo "err hotspot_start_system 系统热点设置里没有名称"; return 1; }
  case "${_c:-1}" in 0) _sec=open ;; 1) _sec=wpa2 ;; 2) _sec=wpa3_transition ;; 3) _sec=wpa3 ;; *) echo "err hotspot_start_system 未知安全类型 $_c"; return 1 ;; esac
  case "${_b:-0}" in 1) _bd=2 ;; 2) _bd=5 ;; 4) _bd=6 ;; *) _bd=any ;; esac
  if [ "$_sec" = open ]; then herald_wifi_cmd start-softap "$_n" open -b "$_bd" > "$W/herald_t6"
  else
    [ -n "$_p" ] || { echo "err hotspot_start_system 系统热点设置里有安全类型但没有密码"; return 1; }
    herald_wifi_cmd start-softap "$_n" "$_sec" "$_p" -b "$_bd" > "$W/herald_t6"
  fi
  herald_wifi_short
}
# V73:hotspot_status —— 热点当前是否开着,一眼能读的几行(详情仍用 wifi_get)。
#   V74 修:① 热点关着时 dumpsys 里没有 mCurrentSoftApInfoMap 行,旧写法把它当成"读不到";现在只要 dumpsys 有输出、
#   没有 SoftApInfo{ 就是 off。② SoftApInfo.toString 是 `bandwidth= 4, frequency= 5180`(等号后有空格,带宽是数字常量),
#   旧写法没处理空格所以 frequency/bandwidth 为空。带宽数字 = SoftApInfo.CHANNEL_WIDTH_*,另给 bandwidth_mhz。
herald_hotspot_status() {
  ( unset LD_LIBRARY_PATH; /system/bin/dumpsys wifi >"$W/herald_dump" 2>"$W/herald_t1" </dev/null )
  if [ ! -s "$W/herald_dump" ]; then
    echo "err hotspot_status dumpsys wifi 没有输出: $(head -c 200 "$W/herald_t1" 2>/dev/null | tr '\n' ' ')"
    rm -f "$W/herald_dump" "$W/herald_t1"; return 1
  fi
  _si=$(grep 'SoftApInfo{' "$W/herald_dump" | head -1)
  _n=$(grep -c 'SoftApInfo{' "$W/herald_dump")
  if [ -n "$_si" ]; then
    _fq=$(printf '%s' "$_si" | sed -n 's/.*frequency= *\([0-9][0-9]*\).*/\1/p' | head -1)
    _bw=$(printf '%s' "$_si" | sed -n 's/.*bandwidth= *\([A-Za-z0-9_]*\).*/\1/p' | head -1)
    echo "hotspot=on"
    echo "frequency=$_fq"
    echo "bandwidth=$_bw"
    case "$_bw" in
      1|2|BANDWIDTH_20MHZ*|*_20MHZ*) _mhz=20 ;; 3|*_40MHZ*) _mhz=40 ;; 4|*_80MHZ) _mhz=80 ;; 5|*_80MHZ_PLUS*) _mhz=80+80 ;;
      6|*_160MHZ*) _mhz=160 ;; 11|*_320MHZ*) _mhz=320 ;; *) _mhz="" ;;
    esac
    echo "bandwidth_mhz=$_mhz"
    case "$_fq" in
      24[0-9][0-9]) echo "band=2.4G" ;; 5[0-9][0-9][0-9]) echo "band=5G" ;;
      59[0-9][0-9]|6[0-9][0-9][0-9]|7[0-9][0-9][0-9]) echo "band=6G" ;; esac
    echo "ap_count=$_n"
    echo "softap_info=$_si"
  else
    echo "hotspot=off"
  fi
  rm -f "$W/herald_dump" "$W/herald_t1"
}

# ---- 命令 ----

# ---- V61 Wi-Fi 热点控制:读写 service-wifi 补丁读取的 Settings.Global 旋钮 ----
  #   6GHz: herald_6g_channel / herald_6g_bw / herald_6g_be;国家码 herald_wifi_country;
  #   通用覆盖(填了就盖过系统「热点」设置里的值,删掉 = 沿用系统):herald_ap_ssid / herald_ap_pass / herald_ap_sec /
  #   herald_ap_hidden / herald_ap_autoshut / herald_ap_clientctl / herald_ap_maxclients / herald_ap_macrand / herald_ap_band /
  #   herald_ap_timeout_min。App 把「key=value」行放进 files/herald_wifi_in(空 value = 删除该项),本命令白名单校验后写入。
  #   读设置由 App 自己用 Settings.Global 直接读(无需权限),broker 只负责写和读热点运行状态。
heraldp_cmdf_wifi_get() {
  arg=$1
              ( unset LD_LIBRARY_PATH; /system/bin/dumpsys wifi >"$W/herald_dump" 2>"$W/herald_t1" </dev/null )
              if [ -s "$W/herald_dump" ] && grep -q 'mCurrentSoftApInfoMap' "$W/herald_dump"; then
                _si=$(grep 'mCurrentSoftApInfoMap' "$W/herald_dump" | grep -m1 'SoftApInfo{')
                { echo "softap_info=${_si:-{\}}"
                  _sc=$(grep -m1 'mSoftApCountryCode' "$W/herald_dump")
                  echo "softap_country=${_sc:-(热点没开时系统不记录)}"
                  echo "driver_country=$(grep -m1 'mDriverCountryCode: ' "$W/herald_dump" | sed 's/.*mDriverCountryCode: //')"; } > "$resp"
              else
                echo "softap_info=UNAVAILABLE $(head -c 200 "$W/herald_t1" 2>/dev/null | tr '\n' ' ')" > "$resp"
              fi
              rm -f "$W/herald_dump" "$W/herald_t1"
              # V68:再附系统热点设置(sys_* 行,只读);已有的三行和读不到时的写法不变
              [ -n "$(tail -c1 "$resp" 2>/dev/null)" ] && echo >> "$resp"
              herald_wifi_sysconf >> "$resp"
}
heraldp_cmdf_wifi_put() {
  arg=$1
              if [ ! -f "$W/herald_wifi_in" ]; then echo "err wifi_put no-payload" > "$resp"
              else
                _ok=0; _fail=0; : > "$W/herald_t3"
                while IFS= read -r _line || [ -n "$_line" ]; do
                  _k=${_line%%=*}; _v=${_line#*=}
                  case "$_k" in
                    herald_6g_channel|herald_6g_bw|herald_6g_be|herald_wifi_country|herald_ap_ssid|herald_ap_pass|herald_ap_sec|herald_ap_hidden|herald_ap_autoshut|herald_ap_clientctl|herald_ap_maxclients|herald_ap_macrand|herald_ap_band|herald_ap_bw|herald_ap_timeout_min) ;;
                    *) echo "skip $_k(not-allowed)" >> "$W/herald_t3"; continue ;;
                  esac
                  # V63:取值校验(V61 实测信道填 70 时热点直接起不来)。不合法的不写,算失败并说明原因。
                  if [ -n "$_v" ] && ! _why=$(herald_wifi_valid "$_k" "$_v"); then
                    _fail=$((_fail+1)); echo "fail $_k=$_v: $_why" >> "$W/herald_t3"; continue
                  fi
                  if [ -z "$_v" ]; then herald_delg "$_k" && _ok=$((_ok+1)) || { _fail=$((_fail+1)); echo "fail delete $_k" >> "$W/herald_t3"; }
                  else herald_setg "$_k" "$_v" && _ok=$((_ok+1)) || { _fail=$((_fail+1)); echo "fail set $_k" >> "$W/herald_t3"; }
                  fi
                done < "$W/herald_wifi_in"
                rm -f "$W/herald_wifi_in"
                if [ "$_fail" = 0 ]; then echo "ok wifi_put $_ok" > "$resp"
                else { echo "err wifi_put ok=$_ok fail=$_fail"; cat "$W/herald_t3"; head -c 300 "$W/herald_t2" 2>/dev/null; } > "$resp"; fi
                rm -f "$W/herald_t3" "$W/herald_t2"
              fi
}
# ---- V62 热点开关(root 才能用 cmd wifi start-softap/stop-softap)+ 后端自检 ----
# hotspot_start 的参数原样交给 start-softap: <ssid> <open|wpa2|wpa3|wpa3_transition> [密码] [-b 2|5|6|any]。
# 按空格切参数,SSID/密码不能带空格(带空格的名称用 herald_ap_ssid 覆盖)。只开放这两个子命令和 status。
heraldp_cmdf_hotspot_start() {
  arg=$1
      if [ -z "$arg" ]; then echo "err hotspot_start no-args" > "$resp"
                     else herald_wifi_cmd start-softap $arg > "$W/herald_t6"; herald_wifi_short > "$resp"; fi
}
heraldp_cmdf_hotspot_stop() {
  arg=$1
      herald_wifi_cmd stop-softap > "$W/herald_t6"; herald_wifi_short > "$resp"
}
heraldp_cmdf_hotspot_start_system() {
  arg=$1
      herald_hotspot_start_system > "$resp"
}
heraldp_cmdf_hotspot_status() {
  arg=$1
      herald_hotspot_status > "$resp"
}
heraldp_cmdf_wifi_status() {
  arg=$1
      herald_wifi_cmd status > "$resp"
}

herald_selftest_wifi() {
  _sv=$(herald_getg herald_6g_channel); echo "settings_get herald_6g_channel=[${_sv}]"
  ( unset LD_LIBRARY_PATH; /system/bin/dumpsys wifi >"$W/herald_dump" 2>"$W/herald_t1" </dev/null )
  echo "dumpsys_wifi_bytes=$(wc -c < "$W/herald_dump" 2>/dev/null) err=[$(head -c 200 "$W/herald_t1" 2>/dev/null | tr '\n' ' ')]"
  rm -f "$W/herald_dump" "$W/herald_t1"
  herald_wifi_cmd status | head -5
}
HERALDP_SELFTEST="$HERALDP_SELFTEST herald_selftest_wifi"
# 附带数据:wifi put 的 key=value 行
HERALDP_ATTACH="$HERALDP_ATTACH wifi_put:herald_wifi_in:raw"
