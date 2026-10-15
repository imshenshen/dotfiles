# 在 macOS 编译和安装新版鼠须管

稳定版更新通道目前提供 Squirrel 1.1.2，但上游主分支已加入云候选所需的 `_refresh_ui` 协议。本文编译上游前端，添加本仓库的云候选原生插件，并应用候选云图标与本地语音的前端补丁，不需要维护远端 fork。上游源码的版本号仍为 1.1.2，因此这里用源码提交号识别构建，不能只看输入法的版本数字。

## 编译版本与依赖

本文脚本默认固定到已验证的上游提交 `0cd71a6130a5866b0ae6ba0494929ebdc8211194`。这次编译使用 macOS 26.5.1、Xcode 26.2、CMake 3.31.2，生成 Apple Silicon 和 Intel 双架构应用。

2026 年 10 月 13 日构建加入第五码顶字和拼音混输。双架构、签名、源码记录和 `_refresh_ui` 检查均通过；隔离测试覆盖连续五笔顶字、拼音歧义保护、退格、分段选词、光标编辑、`zhongguo` 完整拼音及 `zz` 反查。云插件通过模拟响应的异步引擎测试，以及搜狗和 Google 的公开样例实网测试。macOS 要求的退出登录与重新登录由用户在保存工作后完成。

编译的是 Squirrel 前端；librime 1.17.0、Lua 等插件和 Sparkle 2.6.2 使用上游发布的预编译二进制。这是[官方编译说明](https://github.com/rime/squirrel/blob/0cd71a6130a5866b0ae6ba0494929ebdc8211194/INSTALL.md)提供的依赖快捷方式，无需在本机重新编译 Boost 和整个 librime。依赖下载地址固定在该提交的 [action-install.sh](https://github.com/rime/squirrel/blob/0cd71a6130a5866b0ae6ba0494929ebdc8211194/action-install.sh) 中。

需要完整 Xcode 26 或更新版本（语音模块使用 macOS 26 SDK），单独的 Command Line Tools 不够。先从 App Store 安装 Xcode 并启动一次，完成协议确认和组件安装。然后在终端检查：

```sh
xcode-select -p
xcodebuild -version
cmake --version
```

`xcode-select -p` 应指向 Xcode 的 `Contents/Developer`。如果指向 `/Library/Developer/CommandLineTools`，执行：

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

如果尚未安装 CMake，可使用已有的 Homebrew：

```sh
brew install cmake
```

## 一次完成编译和打包

在另一台电脑上先取得这份 dotfiles 仓库及其中的 Rime 文件，然后进入仓库根目录。目录可以不同，脚本自动计算路径：

```sh
cd ~/.dotfiles
bash rime/tools/build_squirrel.sh
```

脚本按顺序执行以下操作：

1. 获取固定的 Squirrel 上游提交，以及该提交固定的 librime、plum 子模块。
   应用 `rime/native/squirrel/` 中的四个补丁，加入浅色小云图标、语音入口、PKG 更新限制和发布安全设置；重复编译会先撤销已知补丁，检查其他源码改动，再重新应用。
2. 运行上游依赖下载脚本，获取官方二进制和默认方案。
3. 编译双架构的 `RimeVoice.app` 和语音桥接库，再用 Xcode 编译 `arm64` 与 `x86_64` 前端，采用本机临时签名。
4. 从 Boost 官方 GitHub 下载并校验 1.89.0 头文件源码包，编译双架构云插件；不需要安装 Homebrew Boost 或启动额外服务。将插件和全部默认方案数据复制进应用包，并预先编译默认词典。
5. 写入源码提交记录，重新签名并验证整个应用包。
6. 制作安装包；安装脚本跳过预置数据的再次编译。

构建文件位于 `rime/.build/`，已经被 Git 忽略。默认脚本固定前端和二进制依赖版本；构建过程中 plum 仍会获取上游预设资源，最终默认方案由仓库 `rime/distribution/data/` 快照及项目配置覆盖。上游下载仍需进一步固定版本和校验。

生成的文件：

```text
rime/.build/squirrel/build/Build/Products/Release/Squirrel.app
rime/.build/squirrel/package/Squirrel.pkg
```

本机开发构建可使用 ad hoc 签名，不需要付费开发者账户。正式发布包使用 Developer ID Application／Installer 签名，需要本机钥匙串中有配套私钥；配置见[签名与公证](signing.md)。当前正式包已签名，按用户决定暂不提交 Apple 公证，因此尚未通过 Gatekeeper 的公证检查。

默认复现本文版本。若将来需要测试不同提交，可以显式指定，固定版本更便于定位回归：

```sh
SQUIRREL_REF=master bash rime/tools/build_squirrel.sh
```

构建目录中若有手工修改，脚本会停止，避免覆盖源码改动。

## 安装到这台电脑

### 其他电脑直接使用已编译的安装包

现在发布的是单个 `rime/dist/Squirrel-版本.pkg`。复制到其他电脑，双击安装后退出登录再登录即可；包内包含默认方案、公共词库、原生组件和可分发的语音默认设置，无需手动导入配置、运行迁移脚本或在目标电脑安装构建工具。详细操作见[单个 PKG 安装与更新](migrate-mac.md)。

更新安装只替换应用，不写 `~/Library/Rime`、用户偏好或钥匙串；本地自定义词、学习词库、热词勾选、配置改动和已保存设置继续保留。由旧临时签名首次切换到正式签名时可能需要重新授权或保存 Key；同身份的正式更新通常可以继承权限，安装器不会删除凭证。

发布资源来自仓库 `rime/distribution/data/`、项目 YAML／Lua 和 `VoiceDefaults.plist`，不从当前用户目录采集。原生改动运行 `build_squirrel.sh`；只改默认资源且已编译过可运行 `package_squirrel.sh`。定制版采用 PKG 更新，关闭上游官方包的自动更新。

### 本机使用安装脚本

完成编译后，在仓库根目录执行：

```sh
bash rime/tools/install_squirrel.sh
```

脚本先备份当前 `/Library/Input Methods/Squirrel.app`，退出正在运行的鼠须管，再备份 `~/Library/Rime`。备份位于 `rime/.build/backups/日期时间.随机后缀/`，包含 `Squirrel.app` 和 `Rime`。新版脚本也将配置文件的符号链接转换成备份目录中的独立文件，避免仓库后续修改使备份内容一起变化。`original.txt` 指向第一次备份，`latest.txt` 指向最近一次备份。

随后 macOS 会显示自己的管理员认证框。密码只在系统认证框输入，脚本不读取或保存密码。安装使用 Apple 的 `installer`，不会更改整个 `/Library/Input Methods` 目录的所有者。

安装结束后，脚本验证应用签名、核对安装后的可执行文件、云插件、语音库及录音助手与构建产物相同、输出源码提交号，重启输入法并触发重新部署。显式重启是为了避免 macOS 在管理员认证期间自动启动旧进程、未加载新插件的情况。macOS 安装器要求退出登录后重新登录，以刷新输入法缓存；请保存其他应用的工作后自行操作，脚本不会自动退出登录。

如果其他电脑尚未启用鼠须管，可在系统设置的键盘输入源中添加它。

## Apple 本地语音

语音功能不需要改个人 YAML。设置中可选择 Apple 本地或[豆包二遍识别](doubao-speech.md)，豆包凭证存入钥匙串。输入法菜单的“语音设置…”可以选择麦克风设备并测试音量；听写时显示动态波形浮条。默认轻按或按住 `Option` 启动，再按一次结束；快捷键支持单独的左右修饰键。设置页还提供共用词典、中英文空格开关和豆包停顿容忍。先在设置页授予麦克风、输入监控和辅助功能权限。跨应用切换后录音继续并显示浮窗预览，结束时无可编辑焦点则在同一黑色浮条中编辑和复制结果；没有独立结果窗口。运行需要 macOS 26、支持新识别引擎的设备和本地中文模型；其他电脑的权限和模型独立配置。操作、手动编辑保护与测试方法见 [Apple 本地语音输入](voice-input.md)。当前源码记录为 `VoiceInputVersion=11`、`SharedUserDictionary=true`、`MixedTextSpacing=true`、`SideSpecificModifierShortcut=true`、`VoiceUndoEnabled=false`、`GlobalDictation=true` 和 `DoubaoSpeechTwoPass=true`。

## 配置五笔与拼音路由

新版 PKG 已包含五笔、拼音反查、白霜词库和混输路由，新电脑无需额外安装词库或链接仓库。旧电脑的用户目录若存在同名配置，会继续优先于包内默认值；需要自行合并更新或备份后移走过期覆盖配置，再重新部署。以下链接方式仅供源码配置维护者使用。个人词典不参与版本管理；新检出仓库可参考 `rime/examples/custom_phrase.txt`，不要覆盖已有个人词典。

已有相应词库时，在终端执行：

```sh
ln -sf "$HOME"/.dotfiles/rime/*.yaml "$HOME"/.dotfiles/rime/*.txt "$HOME/Library/Rime/"
mkdir -p "$HOME/Library/Rime/lua"
ln -sf "$HOME/.dotfiles/rime/lua/wubi_pinyin_router.lua" "$HOME/Library/Rime/lua/"
"/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --reload
```

若仓库不位于 `~/.dotfiles`，替换上述源路径。这里沿用仓库的 `ln -sf` 部署方式，会覆盖目标同名配置链接；安装脚本对已有配置的备份应保留。

## 验证安装

源码构建记录随应用安装。确认提交号及依赖版本：

```sh
plutil -p "/Library/Input Methods/Squirrel.app/Contents/Resources/LocalBuild.plist"
codesign --verify --deep --strict "/Library/Input Methods/Squirrel.app"
lipo -archs "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"
```

提交号应是本文固定的值，架构包含 `arm64` 和 `x86_64`。签名校验成功时没有输出。

`_refresh_ui` 是否编入可执行文件，可以检查：

```sh
strings "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" | grep '^_refresh_ui$'
```

前端协议由本仓库的原生插件使用：后台查询结束后，主队列先更新缓存、重新生成候选，再通知前端刷新。[协议定义](https://github.com/rime/squirrel/blob/0cd71a6130a5866b0ae6ba0494929ebdc8211194/sources/ReservedProperty.swift)、[前端处理](https://github.com/rime/squirrel/blob/0cd71a6130a5866b0ae6ba0494929ebdc8211194/sources/SquirrelInputController.swift)。

`LocalBuild.plist` 应包含 `CloudPinyinVersion = 3`、`CloudBadgeUI = true`、`WubiMixedFifthCode = true`。确认插件架构：

```sh
lipo -archs "/Library/Input Methods/Squirrel.app/Contents/Frameworks/rime-plugins/librime-cloud-pinyin.dylib"
```

切到五笔方案和中文模式，输入 `ggllg`：前四码不立即上屏，第五码提交“一”并留下 `g`；`jjjjj` 提交“日”并留下 `j`。`nihao` 保留整串，显示“你好”，空格确认；退格回四码恢复短码混输。`zhongguo` 查询“中国”，`zznihao` 强制反查“你好”并显示五笔编码。停顿后长串拼音云候选按本地、搜狗、Google 的轮次交错出现，候选文字右下方显示浅色小云图标。`aaaa` 等同时有效的五笔与拼音会暂缓顶字。完整规则、排序和服务开关见[云候选说明](cloud-research.md)。

## 编译流程中处理的两个问题

预置 Rime 数据必须在最终签名前编译。直接使用上游安装脚本时，它会在安装完成后新增 `SharedSupport/build` 文件，导致本地 ad hoc 签名校验失败。本文提前生成这些文件，再签名；打包使用 `rime/distribution/scripts/` 中的安装脚本，仅注册与启用输入源，不在安装时编译或修改签名资源。

默认方案数据由脚本完整复制进应用，避免依赖上游生成 Xcode 资源列表的过程。这样 `quick5` 及其词典也会包含在安装包内。资源处理位于本仓库的构建与打包脚本；前端行为调整以 `native/squirrel/` 补丁维护。

## 恢复原来的输入法

先读出第一次备份的位置：

```sh
backup_dir="$(cat rime/.build/backups/original.txt)"
ls "$backup_dir/Squirrel.app" "$backup_dir/Rime"
```

确认备份存在后，退出新版，将其移到备份目录，再复制原版。保留新版副本，避免直接删除：

```sh
"/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --quit
sudo mv "/Library/Input Methods/Squirrel.app" "$backup_dir/Squirrel.after-upgrade.app"
sudo ditto "$backup_dir/Squirrel.app" "/Library/Input Methods/Squirrel.app"
```

然后退出登录并重新登录。应用恢复不会自动回滚用户词库。若确实需要恢复配置和用户词库，应先退出输入法，将当前 `~/Library/Rime` 另存备份，再复制备份目录中的 `Rime`；恢复词库会丢失备份时间之后的学习记录。

恢复到不含云插件的应用时，当前方案中的 `cloud_*` 组件也需要回滚。备份中的 `Rime/build/wubi86.schema.yaml` 保存当时已部署的完整方案，可用它恢复方案而保留当前用户词库：先将当前 `wubi86.schema.yaml`、`wubi86.custom.yaml` 另存备份，再将该已部署文件复制为用户目录的 `wubi86.schema.yaml`，并把用户目录的 `wubi86.custom.yaml` 替换为 `patch: {}`，最后重新部署。当前配置文件若是符号链接，应先移走链接再写新文件，避免修改仓库源文件。早期备份可能仍保留链接；检查备份内容后再恢复。

2026-10-14 发布修正：主程序与录音助手均包含 NSMicrophoneUsageDescription；源 Info.plist 和打包流程双重保证，发布测试检查最终包内权限说明。禁用额外的中英文状态栏项，保留系统输入源菜单。旧版本 20261014.072758 的首次麦克风授权崩溃由缺少说明引起，需安装修正包并退出登录再登录。

正式发布已支持 Developer ID Application／Installer 双重签名、Hardened Runtime、时间戳以及可选 Apple 公证，操作与认证步骤见[签名与公证](signing.md)。存在本机 release.json 时打包默认复用正式签名配置；生成包不会替换已安装输入法。
