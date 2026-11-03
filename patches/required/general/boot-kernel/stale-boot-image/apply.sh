#!/usr/bin/env bash
# stale-boot-image:
#   删掉因为 framework.jar / services.jar 被改而过期的预编译产物。(不删的话 ART 每次开机退回 memfd 编译,Hunter 等检测会报警。)
#   看"改动标记"决定删什么,不靠别的模块的存在:
#     framework.jar 被改过(was_modified framework/framework.jar)→ 删 boot image(boot / boot-framework)+ services oat
#     只有 services.jar 被改过                                  → 只删 services oat
#     都没改                                                    → 什么也不删,正常退出
#   标记由改 jar 的补丁(build-consistency-dialog-fix、faceunlock、devopts-hide/hook…)在换 jar 之后打(mark_modified)。
# 本模块自己不改任何 jar。必须排在所有改 jar 的模块后面(排前面就看不到它们的标记),原因和删除规则见 README。
# 由 toolkit/build.sh / run-module.sh source,环境见 docs/MODULE-SPEC.md。

FWDIR=$SYS/framework
FW_CHANGED=0; SVC_CHANGED=0
was_modified framework/framework.jar && FW_CHANGED=1
was_modified framework/services.jar  && SVC_CHANGED=1

if [[ $FW_CHANGED == 0 && $SVC_CHANGED == 0 ]]; then
    log "framework.jar 和 services.jar 都没被前面的模块改过,没有过期产物,什么都不删"
else
    need_file framework
    log "改动标记:framework.jar=$FW_CHANGED services.jar=$SVC_CHANGED"

    # 规则(不写死文件名):对每个架构子目录(动态发现),
    #   framework.jar 改过:删 stem 为 boot / boot-framework 的 .art/.oat/.vdex(各带 .fsv_meta),加顶层共享 boot*.vdex
    #     (arm/arm64 里的同名 .vdex 是指向它的符号链接),
    #   framework.jar 或 services.jar 任一改过:删 oat/<arch>/services.{art,odex,vdex}。
    #     services.jar 改了,services.odex 里记的 dex 校验和对不上;framework.jar 改了,boot image 校验和变,
    #     services.odex 即使 services.jar 没动也过期(它编译时依赖 boot image)。所以两种改动都要删它。
    # 其它 boot-<x>.*(ext/okhttp/core-libart/adservices/telephony…)编的是没改的 jar,校验仍然过,保留。
    STEMS=(boot boot-framework)
    mapfile -t ARCHES < <(cd "$FWDIR" && for a in arm arm64; do [[ -d $a || -d oat/$a ]] && echo "$a"; done)
    [[ ${#ARCHES[@]} -ge 1 ]] || die "framework/ 下没有 arm/arm64 预编译目录,底包布局和预期不同"

    TODEL=()
    if [[ $FW_CHANGED == 1 ]]; then
        # 核对:要删的 boot-framework.oat 确实把 framework.jar 编进去了(不是只在 bootclasspath 串里出现)
        for a in "${ARCHES[@]}"; do
            oat=$FWDIR/$a/boot-framework.oat
            sudo test -f "$oat" || continue
            # 直接在二进制里找 dex location(不用 strings | grep -q:pipefail 下 grep 提前关管道会让 strings 收到 SIGPIPE 报错)
            sudo grep -qaF 'framework.jar!classes' "$oat" \
                || die "$a/boot-framework.oat 没有编入 framework.jar,删除规则的前提不成立,请核对底包 boot image 布局"
        done
        for a in "${ARCHES[@]}"; do
            for stem in "${STEMS[@]}"; do
                for ext in art oat vdex; do
                    TODEL+=("framework/$a/$stem.$ext" "framework/$a/$stem.$ext.fsv_meta")
                done
            done
        done
        for stem in "${STEMS[@]}"; do
            TODEL+=("framework/$stem.vdex" "framework/$stem.vdex.fsv_meta")
        done
    fi
    # system_server 的 app image(services.jar 编译产物)。两种改动都会让它过期。
    for a in "${ARCHES[@]}"; do
        for ext in art odex vdex; do
            TODEL+=("framework/oat/$a/services.$ext" "framework/oat/$a/services.$ext.fsv_meta")
        done
    done

    # 实际存在的才删;remove() 跳过不存在的并累加到 REMOVED
    BEFORE=$(cd "$FWDIR" && find . -type f -o -type l | wc -l)
    remove "${TODEL[@]}"
    AFTER=$(cd "$FWDIR" && find . -type f -o -type l | wc -l)
    log "删了过期预编译产物:$((BEFORE - AFTER)) 个(覆盖 ${#ARCHES[@]} 个架构)"
fi
