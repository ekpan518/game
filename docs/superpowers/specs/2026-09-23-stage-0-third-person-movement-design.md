# Equilibrium Arena 阶段 0：第三人称移动原型设计

## 目标与成功标准

本阶段建立一个可由 Godot 4.7 打开并运行的极简 3D 原型。玩家应看到有碰撞的水平地面、基础灯光和胶囊角色，并能用 WASD 按当前镜头方向移动、用鼠标旋转镜头、用 Esc 释放鼠标，再通过单击游戏窗口重新捕获鼠标。

阶段 0 只验证工程能够启动以及第三人称移动和镜头手感。博弈节点、AI、倒计时、Utility、Energy、回合与玩法 UI 均不进入本阶段。

## 当前工程状态

- 工作目录已有一个由 Godot 4.7 创建并打开过的空白工程。
- `project.godot` 已选择 GL Compatibility、D3D12 和 Jolt 物理，但尚未配置主场景或输入动作。
- 当前没有场景和 GDScript 文件。
- `.godot/` 已由现有 `.gitignore` 忽略。
- 开始本设计前目录不是 Git 仓库；本设计阶段已在 `main` 分支初始化仓库，并保留所有现有工程设置和图标文件。
- 当前环境未找到可调用的 Godot 可执行文件，因此自动验证只能覆盖文件、配置和 Git 状态；启动画面与真实输入仍需在 Windows Godot 中验收。

## 方案选择

采用“主场景与玩家场景分离”的结构。它比把所有节点放进一个场景多一个场景文件，但能让后续地图阶段直接复用玩家控制器；相比在运行时完全用代码生成节点，它更容易在 Godot 编辑器中检查碰撞体、相机和灯光。

## 场景结构

### 主场景 `scenes/main/main.tscn`

根节点使用 `Node3D`，包含：

- `WorldEnvironment`：使用简单的程序天空、环境光和背景色，保证无外部资源时场景仍清晰可见。
- `DirectionalLight3D`：提供主方向光并启用阴影。
- `Ground`（`StaticBody3D`）：包含一个 `24 × 0.5 × 24` 的 `BoxMesh` 和相同尺寸的 `BoxShape3D`。地面顶面位于 `y = 0`。
- `Player`：实例化玩家场景，根节点初始位置为 `y = 0.9`，使高 `1.8` 的胶囊底部落在地面顶面上。

主场景设为 `project.godot` 的 `run/main_scene`，因此 F5 可直接运行。

### 玩家场景 `scenes/player/player.tscn`

根节点使用 `CharacterBody3D`，包含：

- `CollisionShape3D`：高 `1.8`、半径 `0.4` 的 `CapsuleShape3D`。
- `MeshInstance3D`：尺寸匹配的 `CapsuleMesh`，使用易识别的纯色材质。
- `CameraYaw`（`Node3D`）：只负责水平旋转，允许连续旋转。
- `CameraYaw/CameraPitch`（`Node3D`）：只负责俯仰，限制为向上 `60°`、向下 `45°`。
- `CameraYaw/CameraPitch/SpringArm3D`：长度为 `4.5` 米，使用物理层 1 检测地面和场景碰撞，并排除玩家自己的碰撞 RID。
- `Camera3D`：作为弹簧臂子节点，保持当前相机状态。

相机枢轴位于角色上半身高度。阶段 0 使用居中跟随视角，不增加肩部偏移、瞄准、缩放或相机模式切换。

## 控制器行为

`scripts/player/player_controller.gd` 只负责玩家运动、镜头和鼠标捕获：

1. `_ready()` 捕获鼠标，并把玩家碰撞体加入弹簧臂排除列表。
2. 鼠标移动在捕获状态下更新水平角和俯仰角；俯仰始终被限制在规定范围内。
3. WASD 通过 `Input.get_vector` 形成二维输入，再使用相机水平朝向转换为世界空间 XZ 方向，因此“前进”始终对应镜头朝向。
4. 水平速度目标为 `5 m/s`；加速率为 `20 m/s²`，减速率为 `24 m/s²`，使用线性趋近避免启动和停止突变。
5. 不在地面时应用 Godot 项目默认重力；不实现跳跃。
6. 每个物理帧只调用一次 `move_and_slide()`。
7. Esc 只释放鼠标。鼠标未捕获时，单击游戏窗口重新捕获；未捕获期间鼠标移动不旋转相机。

输入映射使用 `move_forward`、`move_back`、`move_left` 和 `move_right` 四个动作，分别绑定物理键 W、S、A、D。Escape 和鼠标按钮直接从输入事件处理，避免创建含义不清的额外动作。

## 文档与项目文件

实施阶段将新增或更新：

- `project.godot`：把项目名设为 `Equilibrium Arena`，并配置主场景和输入映射。
- `scenes/main/main.tscn`
- `scenes/player/player.tscn`
- `scripts/player/player_controller.gd`
- `README.md`：非开发者可执行的导入、运行、操作、验收和报错反馈步骤，并记录项目目标 Godot 版本。
- `docs/PROJECT_RULES.md`：记录离线、GDScript、基础 Mesh、分阶段开发和规则/画面分离等约束。
- `docs/GAME_DESIGN.md`：保存初版玩法基线的精炼版本，并明确阶段 0 只实现移动。
- `docs/TODO.md`：阶段 0 标记为本轮目标，阶段 1～4 保持未开始。

不会为了目录外观创建空目录或占位文件，也不会提交 `.godot/` 缓存。

## 验证策略

实施期间先用可执行的静态检查验证文件引用、场景路径、输入动作、禁止范围和 Git 忽略规则，再检查 `git diff --check` 与最终 Git 状态。

如果实施时仍没有 Godot 命令，不会声称项目已在引擎中运行成功。交付报告会把以下两类结果分开：

- 已执行：文件与引用检查、Git 差异检查、缓存忽略检查。
- 待用户确认：Godot 导入/解析、F5 启动、画面、WASD 移动、鼠标旋转、Esc 释放与单击重新捕获。

若之后可获得 Godot 4.7 console 可执行文件，则补充运行：

```powershell
& "C:\path\to\Godot_v4.7-stable_win64_console.exe" --headless --path "E:\game\20260923" --editor --quit
```

该命令用于编辑器级资源和脚本检查，不替代可视化及输入试玩。

## 阶段边界与后续

完成阶段 0 后停止。只有用户明确要求开始阶段 1，才添加中央广场、三处区域、桥梁或道路。任何 AI、节点交互、决策、结算和完整回合功能均推迟到任务书规定的对应阶段。
