# Equilibrium Arena（均衡竞技场）

这是一个分阶段开发的单机 3D 博弈原型。当前只完成阶段 0：水平地面、胶囊角色、第三人称镜头和基础移动。

## 版本与状态

- 工程配置版本：Godot 4.7，渲染方式为 GL Compatibility，3D 物理引擎为 Jolt。
- 已使用 Godot 4.7.2 stable 完成 headless 编辑器导入、原生 Stage 0 all 合约和主场景启动检查；这些自动检查均通过。
- 工程不依赖外部模型、付费素材、网络服务或第三方插件。

## 在 Windows 中打开并运行

1. 启动 Godot 4.7 stable。
2. 在项目管理器中点击“导入”，选择本目录的 `project.godot`。
3. 打开项目，等待右上角资源导入完成。
4. 按 F5 运行项目；如果 Godot 询问主场景，应选择 `scenes/main/main.tscn`。
5. 预期看到一块有光照的绿色地面和一个蓝色胶囊角色。

## 操作

- `W / A / S / D`：按当前镜头方向移动。
- 移动鼠标：水平旋转并上下查看；上下角度有限制。
- `Esc`：释放鼠标，方便操作编辑器或关闭窗口。
- 释放后单击游戏窗口：再次捕获鼠标并恢复视角控制。

## 阶段 0 验收

1. 角色开始时站在地面上，不应持续下落。
2. 同时按两个方向键时，斜向移动不应明显快于直线移动。
3. 鼠标可以环绕角色旋转，向上和向下查看不会翻转镜头。
4. 靠近地面观察时，镜头不应穿进地面；胶囊本身不应把镜头顶到近处。
5. 按 Esc 后移动鼠标不再旋转视角；单击游戏窗口后视角控制恢复。

headless 自动检查不能代替 F5 的画面、手感和真实键鼠输入验收，仍需用户完成上述人工试玩。

## 出错时请提供

请提供 Godot 的完整版本号、发生问题前的操作步骤、运行窗口截图，以及 Godot 底部“输出”和“调试器”面板中的完整报错文本。若问题与操作有关，请同时说明按了哪些键、是否先按过 Esc、问题能否每次复现。

## 可执行检查

静态契约检查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify_stage0.ps1 -Scope all
```

已验证的 Godot 4.7.2 stable 检查（在 PowerShell 中从项目根目录运行）：

```powershell
$godot = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --editor --quit
& $godot --headless --path . --script res://tests/stage0/test_stage0.gd -- --scope=all
& $godot --headless --path . --quit-after 3
```

头部模式不能代替 F5 画面和操作验收。
