# bootanim-portrait — 开机动画竖屏适配

## 问题

Pixel Tablet(tangorpro)的 `product/media/bootanimation.zip` 是按它的横屏面板做的:`desc.txt` 写 `2560 1600 60`。
TB321FU 面板的自然方向是**竖屏 1600x2560**(见 `rotation-fix`)。DP11(A17)上开机动画比例严重错乱、像横竖屏弄反了(用户 2026-11-06 实测 test-v1.2)。

## 做法

构建时现取底包的动画(不在仓库里放 Google 的素材),用 `rotate_bootanim.py`(纯 Python,不依赖 PIL):

- `desc.txt` 第一行宽高对调 → `1600 2560 60`,其余行(dynamic_colors、各 part)不动;
- 每帧 PNG 转 90°(默认顺时针);
- 各 `partN/trim.txt`(每帧在画布里的裁剪框 `wxh+x+y`)按同一旋转换算:顺时针 `(x,y,w,h) → (1600-y-h, x, h, w)`;
- 全部 Stored + `zipalign 4`(bootanimation 要求不压缩)。

动画尺寸和屏幕一样大,不再有缩放/裁切。

## 方向

`BOOTANIM_ROTATE=cw`(默认):平板逆时针横过来(系统横屏 = `ROTATION_90`,rotation-fix 实测)时 "Powered by android" 等文字正立。
真机上若是倒的,`BOOTANIM_ROTATE=ccw` 重打。

## 适用

底包动画已经是竖屏尺寸时(宽 ≤ 高)自动跳过。目前只放进 DP11 的 device.conf(ap3a/bp1a 线用户没反馈这个问题,未加)。
