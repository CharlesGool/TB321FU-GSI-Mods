# desktop-unlimited:去掉 A17 桌面模式(桌面窗口)同时开应用的数量上限(默认 4 个,超了最早的被最小化)。
# WMShell(SystemUI 里)的 DesktopConfig:maxTaskLimit = SystemProperties.getInt("persist.wm.debug.desktop_max_task_limit",
#   framework 的 config_maxDesktopWindowingActiveTasks);maxTaskLimit <= 0 时不创建 DesktopTasksLimiter = 不限。
# 只往 system build.prop 写默认值;persist 属性,用户之后 setprop 改了以 /data 里的为准。
LIMIT=${DESKTOP_MAX_TASKS:-0}
[[ $LIMIT =~ ^[0-9]+$ ]] || die "DESKTOP_MAX_TASKS 必须是非负整数(0 = 不限),现在是 '$LIMIT'"
prop build.prop persist.wm.debug.desktop_max_task_limit "$LIMIT" --add
log "桌面模式应用数上限:$([[ $LIMIT == 0 ]] && echo 不限 || echo "$LIMIT 个")"
