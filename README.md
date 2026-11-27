# 烈焰突袭 (BlazeRush)

霓虹肉鸽竖屏动作游戏：保留极简 **移动 / 射击 / 必杀** 三键操作，融入波次三选一强化、掉落补给与领主战。

## 玩法与特性（v2.0.0）

- **极简三键操控**：圆形发光虚拟摇杆移动 + 右侧射击（自动锁定最近目标并显示准星）+ 蓄能必杀「烈焰冲击」
- **波次三选一肉鸽强化**：每波清场后从 12 种强化（扇形齐射、贯穿射线、电弧弹射、烈焰暴击、脉冲护盾、战意虹吸、超新星扩域等）中择一构筑流派
- **6 类敌人 + 每 5 波领主战**：追击者 / 霓虹射手（带瞄准前摇）/ 重装蛮锤 / 突进猎手（激光冲锋预警）/ 裂变核心（死后分裂）/ 烈焰领主 Boss（多阶段弹幕与专属血条）
- **战斗掉落补给**：能量晶核、生命结晶、烈焰过载核心（短时狂暴射速 + 额外弹丸）
- **视觉与手感**：传送门刷怪预警、浮空伤害与暴击跳字、动态连击槽、屏幕震动、顿帧、粒子火花与安卓震动反馈
- **完善控制**：标题页与暂停页支持独立开关音乐 / 音效 / 震动；支持安卓系统返回键暂停；标题页右上角显示当前版本并自动检查 GitHub Releases 新版本
- 桌面调试：`WASD` 移动，`空格/J` 射击，`K/Shift` 必杀，`Esc` 暂停

## 要求

- Godot **4.7.x**
- Android 导出见 [`docs/android-signing.md`](docs/android-signing.md)

## 发布与导出 APK

正式 APK 通过推送与版本号一致的标签发布（例如 `v2.0.0`）。GitHub Actions 会用仓库 Secrets 里的同一把项目密钥签名，并挂到 [Releases](https://github.com/JeffGu98/BlazeRush/releases)。流程和密钥备份说明见 [`docs/android-signing.md`](docs/android-signing.md)。不要把密钥提交进本仓库。

本机构建：

```bash
./tools/export_android.sh
```

产物默认：`build/BlazeRush-<version>.apk`（arm64-v8a）。

## 自测

```bash
godot --headless --path . -s res://tools/selftest.gd
```
