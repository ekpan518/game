# Bumper Arena（碰碰竞技场）

Bumper Arena 是一个使用 Godot 4.7.2 与纯 GDScript 制作的单人碰碰车淘汰原型。玩家在没有护栏的悬空圆形平台上对抗三辆 AI 车辆，目标是把所有对手撞下平台并成为最后的存活者。项目只使用 Godot 内置节点、网格、材质和脚本，不需要外部素材或插件。

## 在 Windows 上运行

1. 安装或解压 Godot 4.7.2 stable。
2. 用编辑器导入本目录中的 `project.godot`，等待首次资源导入完成。
3. 打开项目后按 F5 运行主场景。

首次检出或清空 `.godot` 缓存后，必须先做一次编辑器导入，再执行原生测试；这样 Godot 才能注册所有带 `class_name` 的强类型脚本。

## 操作

- W：前进。
- S：先刹车，接近静止后倒车。
- A / D：向左 / 向右转向。
- 移动鼠标：水平环绕并调整有限俯仰的第三人称镜头。
- Esc：释放鼠标。
- 单击游戏窗口：重新捕获鼠标。
- 比赛结束后按回车或单击“重新开始”。

## 比赛规则

- 每局是一名玩家对三辆 AI，共四辆性能完全相同的碰碰车。
- 车辆从距平台中心约 6 米的位置出发，并朝向中心。
- 车辆坠落后永久淘汰；没有复活或多条命。
- 最近一次有效冲撞发生在淘汰前 4.0 秒内时，击杀归属于该攻击者。
- 存活的击杀者获得一层强化，最多三层；每层增加输出击退并降低承受击退，但不改变速度和转向。
- 玩家被淘汰即显示“失败”；玩家成为唯一存活者时显示“胜利！”。同一物理帧内玩家与最后一辆 AI 同时坠落时按失败处理。
- 结果出现后所有存活车辆冻结；“重新开始”会重建主场景并恢复四车、零强化与隐藏结果面板。

## 自动验证

以下命令在项目根目录运行。新检出必须保持“编辑器导入 → Godot 版本 → 原生测试 → 原生非法 scope → 静态测试 → 静态非法 scope → 启动 → Git 卫生”的顺序。两个非法 scope 命令预期返回非零，其余命令预期返回 0。

```powershell
$godot = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --editor --quit
& $godot --version
& $godot --headless --path . --script res://tests/bumper/test_bumper_arena.gd -- --scope=all
& $godot --headless --path . --script res://tests/bumper/test_bumper_arena.gd -- --scope=typo
powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify_bumper_arena.ps1 -Scope all
powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify_bumper_arena.ps1 -Scope typo
& $godot --headless --path . --quit-after 5
git diff --check
git ls-files -- '.godot/*'
git ls-files -- '*.uid'
git ls-files -- 'addons/*'
git status --short --branch
```

原生测试的有效 scope 为 `rules`、`vehicle`、`match`、`ai`、`world` 和 `all`；PowerShell 验证器还支持 `docs`。原生行为测试是正确性的权威证据，静态验证器只补充检查文件结构、配置与仓库卫生。

## 人工验收清单

以下 F5 画面、输入和驾驶手感仍待人工验收，自动化通过不能替代这些检查。

1. 按 F5 后确认圆形平台、程序化天空、方向光、四种高对比车色以及左上角 HUD 都清晰可见。
2. 用 W/S/A/D 检查前进、制动、倒车、低速转向和高速转向的手感。
3. 移动鼠标检查镜头环绕与俯仰，再用 Esc 释放并单击窗口重新捕获。
4. 分别进行低速擦碰和高速正面冲撞，确认高速撞击明显更强、车辆保持直立且不会异常穿透。
5. 观察三辆 AI 的追击、边缘回正、目标切换与卡住恢复，并完成一次胜利和一次失败。
6. 在结果界面同时尝试按钮与回车重新开始，确认新一局恢复四辆存活车辆、零强化且结果面板隐藏。

## 报告问题

提交问题时请附上 Godot 完整版本、可重复的复现步骤、问题截图，以及编辑器“输出”和“调试器”面板中的完整信息。若问题只在某一输入、某次碰撞或重新开始后出现，也请说明发生前的操作顺序。
