# THIRD_PARTY_NOTICES — Third-Party Notices

English · [Español](../es/THIRD_PARTY_NOTICES.md) · [简体中文](../THIRD_PARTY_NOTICES.md)

Third-party materials distributed by this repository, along with their attribution, license, and compliance obligations. This repository's own code (patches, `toolkit/`, docs) is released under GPL-3.0-or-later.

## Third-party notices

### Component list

| Component | Version/Hash | Upstream | License | How it is used | Copyright holder | Compliance obligations | Verified on |
|---|---|---|---|---|---|---|---|
| avbtool | AOSP | android.googlesource.com (platform/external/avb) | MIT | `toolkit/avb/avbtool.py`, distributed with the repo and called by the AVB signing scripts | The Android Open Source Project | Keep the copyright and license notice (in the file header) | 2026-11-04 |
| herald-core | See that repository | github.com/CharlesGool/herald-core | GPL-3.0-or-later, etc. (see that repository) | `patches/required/general/herald-core` is a synced copy of its `patch/` (the author's own work, not an external third party) | CharlesGool | Same as herald-core | 2026-11-04 |
| tb321fu-tango-patch | See that repository | github.com/CharlesGool/tb321fu-tango-patch | GPL-3.0-or-later, etc. (see that repository) | `patches/required/general/tango` is a synced copy of its `patch/` (the author's own work, not an external third party; Tango itself, `tango32.ko` and the Xiaomi 32-bit libraries are not included) | CharlesGool | Same as tb321fu-tango-patch | 2026-11-05 |

### License texts

- This repository: GPL-3.0-or-later. The full text is in `LICENSE`.
- avbtool: MIT. The full copyright and license text is in the file header of `toolkit/avb/avbtool.py`.

### Source code availability

This repository distributes patch source, build scripts, and documentation, all in source form, so there are no additional source-offer obligations. Build outputs (the system image, the 9008 package) are not in this repository.

### Compliance review

- Copyleft components: this repository itself is GPL-3.0-or-later. `avbtool.py` (MIT) is compatible with GPL-3.0.
- **Proprietary components not distributed with this repository**: the Megvii SDK needed for face unlock, and the face education page assets used by Pixel settings (`face_education_lottie.json`, `face_settings.mp4`). These are proprietary and provided by the upstream ParanoidSense repository; they are fetched with `fetch_upstream.sh` at build time. `FaceUnlock.apk` and `FaceUnlockSettingsOverlay.apk`, which contain them, are not in the repository either and must be built locally (see the READMEs under `patches/required/tangorpro/<base>/faceunlock`). Before 2026-11-05 `FaceUnlockSettingsOverlay.apk` was tracked, and older commits still contain it. External build tools (Android NDK, apktool, dex2jar, xdelta3, etc.) are not in the repository and must be supplied by the user.
