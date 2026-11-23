# 烈焰突袭 (BlazeRush)

短局竖屏动作游戏：只有 **移动 / 射击 / 必杀** 三个操作。

## 玩法

- 左虚拟摇杆移动，右侧 **射击** 自动瞄准近敌开火
- **必杀** 蓄满后释放「烈焰冲击」，范围清场并震退敌人
- 波次无尽，打分与连击；三种敌人：追击者 / 射手 / 蛮锤
- 桌面调试：`WASD` 移动，`空格/J` 射击，`K/Shift` 必杀
- 自带循环 BGM；Android 上开火/受击/必杀会震动反馈

## 要求

- Godot **4.7.x**
- Android 导出见 [`docs/android-signing.md`](docs/android-signing.md)

## 发布与导出 APK

正式 APK 通过推送与版本号一致的标签发布（例如 `v1.2.0`）。GitHub Actions 会用仓库 Secrets 里的同一把项目密钥签名，并挂到 [Releases](https://github.com/JeffGu98/BlazeRush/releases)。流程和密钥备份说明见 [`docs/android-signing.md`](docs/android-signing.md)。不要把密钥提交进本仓库。

本机构建：

```bash
./tools/export_android.sh
```

产物默认：`build/BlazeRush-<version>.apk`（arm64-v8a）。

## 自测

```bash
godot --headless --path . -s res://tools/selftest.gd
```
