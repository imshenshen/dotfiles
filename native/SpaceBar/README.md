# SpaceBar

一个原生 macOS Space 条。沿用 dotfiles 中 simple-bar 的深色圆角容器、灰色标签、白色焦点标签和 Q/W/E/R/T/Y/U/I/O 提示。仅实现 Space 显示、切换和重命名，不包含时钟、日历或窗口列表。

## 构建与运行

需要 macOS 13+、Xcode / Swift 5.9+，以及运行中的 yabai。

```sh
./scripts/build-app.sh
open dist/SpaceBar.app
# 首次对照旧条：默认下移到 44pt，避免重叠（已有位置偏好优先）
open dist/SpaceBar.app --args --trial
```

可将 `dist/SpaceBar.app` 复制到 `~/Applications` 后打开。应用会在右侧系统菜单栏提供位置调整、刷新和退出入口，不显示 Dock 图标。复制后退出旧实例再打开新实例，事件回调会更新到新路径。

```sh
# 仅检查真实 yabai 数据，不切换或修改 Space
./dist/SpaceBar.app/Contents/MacOS/SpaceBar --check
# 测试
swift test --disable-sandbox
```

默认查找 `/opt/homebrew/bin/yabai` 或 `/usr/local/bin/yabai`。自定义路径后重新启动：

```sh
defaults write local.spacebar.app yabaiPath /absolute/path/to/yabai
```

## 使用

- 单击 Space 切换；Option 单击或右键菜单重命名。保存时才向 yabai 提交一次。
- 右键任意标签或条的空白区域 →“设置…”；系统菜单栏也提供设置入口。颜色、圆角、位置和动画速度即时生效并自动保存，可一键恢复默认。
- 选中背景使用独立弹簧动画，滑动时轻微拉伸；中途切换保留当前坐标和速度，连续点击以最后目标为准。动画结束后停止计时器。
- 可关闭动画；尊重系统“减少动态效果”。设置窗口可用 Command-W 关闭。
- 白色标签表示焦点；浅色描边表示另一屏上可见的 Space。
- Q/W/E… 沿用原 simple-bar 的编号提示。快捷键仍由已有 skhd 配置处理，应用不注册全局热键。
- 每屏一个条，按真实显示器 ID 匹配当下的 yabai display index；拔屏时移除对应窗口。
- 默认放在系统菜单栏 / 刘海安全区域下方 8pt。右上角菜单可上移、下移或重置。
- 标签过多时可横向滚动，长名称截断，悬停查看全名。全屏 Space 默认隐藏。
- 不主动更改菜单栏自动隐藏、不更改 yabai padding、也不操作现有 arrangeSpace / bindSpace 脚本。

## 与 Übersicht 并存和迁移

初次运行保留原 Übersicht，不会替你停掉其他小组件。测试时可以在 SpaceBar 菜单中下移条，避免与旧条重叠。确认替换后，在 Übersicht 的 Widgets 菜单中关闭 `simple-bar/index.jsx`，然后恢复 SpaceBar 默认位置。

旧 simple-bar 曾在 yabai 注册 `Refresh simple-bar ...` 事件。只关闭 widget 不一定能清理这些旧事件；需要用 `yabai -m signal --list` 检查，并按确切 label 移除仅属于 simple-bar 的事件，或停用旧 widget 后重启 yabai。不要删除现有跨屏布局信号。SpaceBar 不自动清理别的程序的信号。

名称直接存储在 yabai label 中。应用不建立第二份名称数据库；yabai 重启后的 label 恢复继续遵循你的 yabairc / arrangeSpace.sh。

## 性能与边界

- 原生 AppKit，无 WebView、JavaScript 运行时或 AppleScript 刷新。
- 监听 Space / 显示器事件，经 60ms 合并后查询 spaces 和 displays；不查询 windows。
- 所有屏幕共用一次状态查询；状态没变化不重建视图。
- 每 30 秒做一次状态校准；每至少 60 秒检查自己的信号是否丢失，用于 yabai 重启恢复。
- 注册的信号全部以 `local.spacebar.` 开头，正常退出清理自己的信号。强制退出后可重开并正常退出完成清理。
- 命令在后台运行，3 秒超时；名称以独立参数传入，不经 shell。只有事件 helper 路径进行 shell 引号转义。
- 切换前重新查询 Space ID 对应的当前 index，避免使用 UI 中旧序号；极端并发拓扑改变仍应等稳定后重试。
- yabai 离线时隐藏旧按钮，在系统菜单显示错误；不显示虚假的切换成功状态。
- 不添加权限绕过，不自动修改 SIP；切换能力取决于已安装 yabai 和当前系统配置。
- 本地开发构建采用 ad-hoc 签名，未公证。不包含开机启动配置或自动更新。

多屏热插拔、休眠、原生全屏和实际切换耗时仍需在对应硬件场景中验收。

## 本次验证

2026-09-21：release 构建和 ad-hoc 签名通过；6 项 XCTest 通过；真实 yabai 读取 1 块显示器、9 个 Space 成功；应用已启动，原生条截图和右键重命名菜单已检查，9 个事件订阅注册成功。多屏热插拔、休眠恢复及完整重命名提交仍需交互验收。

2026-09-21 更新：加入可重定向的液态选中动画和原生设置窗口；10 项测试通过，覆盖快速反向、位置/速度连续性、帧率独立性及配置保存。已在运行中的应用验证右键“设置”入口及窗口布局。

崩溃修复：旧动画中的 `NSString.draw` 字体/颜色属性转换路径会抛出 `NSInvalidArgumentException`（与实际崩溃报告栈一致）。新增离屏绘制回归测试在旧代码上复现了同一异常；现改为明确传入 CTFont、CGColor 的 CoreText 绘制，连续 3,000 帧通过，全部 11 项测试通过。保留滑动、变形和中途改目标能力。

尺寸设置：右键 → 设置，可调整工具条高度（最高 64pt）和文字大小（9–24pt）。最低高度随字号调整，以防裁切；快捷键提示、标签宽度、圆角和选中背景跟随尺寸变化。新增配置字段向后兼容，旧版颜色及动画偏好不会重置。12 项测试通过，包含旧配置迁移和多字号绘制回归。

性能优化：Space 名称和快捷键的 CoreText 排版结果会按名称、字号和可用宽度缓存。选中背景动画仅改变绘制颜色，不再每帧重新排版文字；白框移动时也只重绘旧位置、新位置及与其相交的标签。动画帧率跟随当前屏幕（30–120Hz），结束后停止计时器。新增缓存回归测试验证 1,000 个颜色动画帧只建立一次文字布局；现有 3,000 帧绘制测试耗时由约 0.13 秒降至约 0.08 秒。全部 13 项测试通过。
