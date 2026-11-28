## Kitsune Mask 30.7（狐狸面具）

这是本项目在 GAMEMT E5 Ultra（UMS9230，Android 14）上实际使用并验证通过的 Kitsune Mask 30.7 安装包，作为**存档副本**随仓库发布，方便复现者直接取用。

### 文件信息

| 项 | 值 |
| --- | --- |
| 文件名 | `Kitsune_30.7_140326.apk` |
| 大小 | 21029893 字节（20.06 MB） |
| SHA256 | `18A0F7B96A930BCC26BA705073AB0436DF7C4E26EC4B01A678655435F9776A9F` |
| 包名 | `io.github.x0eg0.magisk` |
| versionCode / versionName | `30700` / `v30.7-kitsune` |
| targetSdk | 36 |
| 本机 root 标识 | `magisk -v` → `46f5f839-kitsune:MAGISK:R` |

下载后请先核对 SHA256，不一致就不要安装。

### 为什么放在 Release 而不在仓库目录里

仓库的 `.gitignore` 排除了 `*.apk`，第三方二进制不进入 git 历史（避免仓库体积膨胀），需要时通过 Release 附件获取。

### 来源与授权说明

- Kitsune Mask（狐狸面具）是 Magisk 的衍生分支，遵循 **GPL-3.0**，本仓库仅作二进制存档与分发，不是作者，也不承担其上游代码的任何担保。
- HuskyDG 的原始分发仓库 `HuskyDG/magisk-files` 已删除，本包来自第三方接续构建（包名 `io.github.x0eg0.magisk`），**不是官方签名**。这一点在 `AI-GUIDE.md` 第四节也标注为"未验证的上游"。
- 安装前请自行评估：非官方签名 + 非官方来源，存在被二次打包的风险。核对上面的 SHA256 能确认你拿到的和本项目实测的是同一个文件，但不能证明它没有被上游篡改。

### 安装方式（本项目实测路径）

1. 设备已完成 BL 解锁（`ro.boot.flash.locked=0`）
2. 本项目的做法是 headless 打补丁，不依赖手机 GUI：从 APK 解出 `assets/boot_patch.sh`、`lib/arm64-v8a/libmagiskboot.so → magiskboot` 等组件，对**原厂** `init_boot.img` 打补丁后刷双槽
3. 手动安装也可以：直接 `adb install -r Kitsune_30.7_140326.apk`，打开后按提示修补 `init_boot`，再 `fastboot flash init_boot` 到 `_a` 和 `_b` 两个槽
4. 若设备上已有其他 Magisk（如 31.1 或 27001），**先卸载再装**，不同签名的面具互相覆盖会导致 root 状态异常

详见 [docs/02-magisk-root.md](../docs/02-magisk-root.md)。
