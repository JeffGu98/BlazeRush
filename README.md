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

## 导出 APK

```bash
./tools/export_android.sh
```

产物默认：`build/BlazeRush-<version>.apk`（arm64-v8a）。

## 自测

```bash
godot --headless --path . -s res://tools/selftest.gd
```
