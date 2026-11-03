# adaptive-refresh-fix — 自适应刷新率修复(补回原厂的刷新率定时器)

## 为什么
V75 测试发现设备上没有 `ro.surface_flinger.set_idle_timer_ms`,静止时一直 165Hz,也没有触摸/视频感知。这批属性原厂在 `system/build.prop`(stock-build.prop/system_build.prop 第 290–295 行),Mystic GSI 没带。

## 做什么
把原厂的值写回 `build.prop`:空闲 2 秒降档、触摸后 2 秒内升档、手写笔 10 秒、`set_refresh_timer_ms=200`、桌面 30 秒;内容检测(视频按帧率选档)原厂在 vendor 里已经开着,这里重复声明无害;输入 fling/scroll 的 boost 阈值也一并补回。

这是 SurfaceFlinger 原生的触摸感知、视频感知、空闲降档,比后端每 5 秒轮询的做法快、省电。`refresh` 命令和 `refresh-rate/adaptive` 只管"范围/规则",原生定时器在范围里挑具体档位:用 `refresh range 30 165`(或 `auto`)让它有得挑;`refresh set N` 锁定会让定时器没有可调空间。

## 没在真机上核对
- 开机后 `getprop ro.surface_flinger.set_idle_timer_ms` 应为 2000。
- 静止几秒后 `heraldctl refresh status` 的 `active` 应降到范围下限;滑动时升到范围上限;全屏视频按帧率匹配档位。
- 属性只在 SurfaceFlinger 启动时读,需要整机重启。
