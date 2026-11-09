# 构建入口。真正干活的是 toolkit/ 下的脚本,这里只是把常用的组合写短。
#
#   make list                              看全部补丁和这次打哪些
#   make info P=battery                    看一个补丁的身份(patch.conf)和谁依赖它
#   make menu [SAVE=名字]                  勾选菜单;SAVE 存成预设
#   ./make-9008.sh                         交互式一个一个问,再出 9008 包(推荐)
#   make build                             GSI 底包 + 原厂固件 → 依次打补丁 → system 镜像 + vbmeta_system + boot 集
#   make 9008 NOTE="备注"                  build + 打 9008 刷机包
#   make pack NOTE="备注"                  只打包,复用已有的 build 输出
#   make survey BASE_GSI=新底包.img        换底包摸底:每个补丁在新底包上单独跑,出兼容性报告和建议预设
#   make test                              补丁独立性测试(每个补丁单独在干净底包上跑)
#   make unit                              broker/heraldctl 插件的单元测试(不碰真机)
#   make sync-core                         从 herald-core 仓库同步 patches/required/general/herald-core(那个补丁以它为准,别直接改副本)
#   make sync-tango                        从 tb321fu-tango-patch 仓库同步 patches/required/general/tango(同上,以它为准)
#   make sync-faceunlock                   从 tb321fu-faceunlock-patch 仓库同步各底包的 faceunlock(同上)
#   make sync-video-freeze                 从 tb321fu-video-freeze-patch 仓库同步 patches/required/general/hardware-fix/video-freeze-fix(同上)
#
# 选补丁(所有目标通用):
#   PROFILE=名字     预设,devices/<设备>/profiles/<名字>.txt 或 profiles/<名字>.txt
#   WITH=规则,…      加上     WITHOUT=规则,…   去掉
#   规则:补丁名(battery、brightness/hbm-unlimited)、文件夹(slim、perf)、通配(hotspot-*)、all
# 例:make 9008 WITHOUT=tango NOTE="不带 32 位"
#
# 其他变量:DEVICE(默认 tb321fu-a15)、CONF(默认 devices/$(DEVICE)/device.conf)、OUT(默认 /tmp/9008-out/$(DEVICE),必须在本机磁盘)

DEVICE ?= tb321fu-a15
CONF   ?= devices/$(DEVICE)/device.conf
OUT    ?= /tmp/9008-out/$(DEVICE)
export PROFILE WITH WITHOUT

.NOTPARALLEL:
.PHONY: list info menu build 9008 pack survey test unit sync-core sync-tango sync-faceunlock sync-video-freeze

list:
	@toolkit/select.sh $(CONF) --list

info:
	@test -n "$(P)" || { echo '用法: make info P=补丁名'; exit 1; }
	@toolkit/select.sh $(CONF) --info $(P)

menu:
	@toolkit/select.sh $(CONF) --menu $(if $(SAVE),--save $(SAVE))

build:
	toolkit/build.sh $(CONF) $(OUT)

9008:
	@test -n "$(NOTE)" || { echo '缺 NOTE="版本备注"'; exit 1; }
	toolkit/build-9008.sh $(CONF) $(OUT) --note "$(NOTE)"

pack:
	@test -n "$(NOTE)" || { echo '缺 NOTE="版本备注"'; exit 1; }
	toolkit/build-9008.sh $(CONF) $(OUT) --note "$(NOTE)" --reuse

survey:
	@test -n "$(BASE_GSI)" || { echo '用法: make survey BASE_GSI=新底包.img'; exit 1; }
	toolkit/survey.sh $(CONF) $(BASE_GSI)

test:
	toolkit/tests/test-modules.sh $(CONF) --solo

unit:
	@toolkit/sync-herald-core.sh --check
	@toolkit/sync-tango.sh --check
	@toolkit/sync-faceunlock.sh --check
	@toolkit/sync-video-freeze.sh --check
	@set -e; for t in toolkit/tests/test-*-plugin*.sh toolkit/tests/test-herald-start-prefix.sh toolkit/tests/test-slim-lists.sh toolkit/tests/test-smooth-display-hook.sh toolkit/tests/test-patch-scope.sh toolkit/tests/test-image-name.sh toolkit/tests/test-camera-choice.sh toolkit/tests/test-google-slim.sh toolkit/tests/test-qs-tiles.sh toolkit/tests/test-herald-apps.sh toolkit/tests/test-torch-plugin.sh \
	    "toolkit/tests/test-herald-start-full.sh --repo" "toolkit/tests/test-herald-protocol.sh $(CONF)"; do \
	    echo "== $$t"; out=$$(bash $$t 2>&1) || { echo "$$out" | tail -n 30; echo "失败: $$t"; exit 1; }; echo "$$out" | tail -1; done

sync-core:
	toolkit/sync-herald-core.sh

sync-tango:
	toolkit/sync-tango.sh

sync-faceunlock:
	toolkit/sync-faceunlock.sh

sync-video-freeze:
	toolkit/sync-video-freeze.sh
