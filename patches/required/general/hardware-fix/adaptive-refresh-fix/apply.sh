# 把原厂 system/build.prop 里的 SurfaceFlinger 定时器补回来(Mystic GSI 没带)。原理见 README.md。
need_file build.prop
prop build.prop ro.surface_flinger.set_idle_timer_ms 2000 --add
prop build.prop ro.surface_flinger.set_touch_timer_ms 2000 --add
prop build.prop ro.surface_flinger.set_pen_timer_ms 10000 --add
prop build.prop ro.surface_flinger.set_refresh_timer_ms 200 --add
prop build.prop ro.surface_flinger.set_launcher_timer_ms 30000 --add
prop build.prop ro.surface_flinger.display_update_imminent_timeout_ms 1000 --add
prop build.prop ro.surface_flinger.use_content_detection_for_refresh_rate true --add
prop build.prop ro.config.lgsi.input_fling.boost_velocity 100 --add
prop build.prop ro.config.lgsi.input_scroll.boost_distance 100 --add
