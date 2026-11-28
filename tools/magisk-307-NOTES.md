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

### 安装方式

**情形 A · 还没有 root（首次）**：装 APK 不需要 root，让 App 自己产出补丁镜像，再用 fastboot 刷双槽。

1. `adb install -r Kitsune_30.7_140326.apk`
2. 原厂 `init_boot.img` 推到 `/sdcard/Download/`
3. 面具主页「安装」→「选择并修补一个文件」→ 选 `init_boot.img`
4. `adb pull /sdcard/Download/magisk_patched-30700_*.img`
5. `fastboot flash init_boot <镜像> --slot all`

**情形 B · 已经有 root（换面具 / 升级）**：装上即可在 App 内直接完成，不用 fastboot。

1. 装 Kitsune APK（包名 `io.github.x0eg0.magisk`，可与旧面具共存安装）
2. 打开后「安装」→「直接安装（推荐）」→ 自动重打补丁并写入 `init_boot`
3. 重启，`magisk -v` 变成 `46f5f839-kitsune:MAGISK:R` 即接管成功
4. **确认接管成功后再卸载旧面具**（顺序反了会两个 daemon 抢同一个 magiskd）

本项目当初走的是 headless 路径（从 APK 解出 `assets/boot_patch.sh`、`lib/arm64-v8a/libmagiskboot.so` 等组件在机内打补丁），适合脚本化复现；GUI 路径适合个人手动操作，两条路的产物等价。

两种情形都别做：给已经打过补丁的镜像再打一次补丁；同时装两个面具并都点"直接安装"。

详见 [docs/02-magisk-root.md](../docs/02-magisk-root.md) 的「图形界面路径」一节。
