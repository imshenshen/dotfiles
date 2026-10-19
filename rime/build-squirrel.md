# 在 macOS 编译和安装新版鼠须管

> 当前状态（2026-10-17）：`20261017.063732` / `20261017.065108` 候选包撤回。强制退出登录已取消，未安装的辅助功能实时写入扩展已从源码移除，仅保留 iTerm2 语音提交修复。安装失效根因仍在调查；用户已授权生成最小范围包用于安装对照测试，真实验收待完成。下文旧记录中的 RequireLogout 决策已被本段取代。

稳定版更新通道目前提供 Squirrel 1.1.2，但上游主分支已加入云候选所需的 `_refresh_ui` 协议。本文编译上游前端，添加本仓库的云候选原生插件，并应用候选云图标与本地语音的前端补丁，不需要维护远端 fork。上游源码的版本号仍为 1.1.2，因此这里用源码提交号识别构建，不能只看输入法的版本数字。

## 本机正式编译、签名与分发（当前流程）

这台电脑已配置 Developer ID Application／Installer 证书、配套私钥和本机签名配置，无需再申请签名证书。正式分发现在还要求 Apple 公证。首次在自己的本机终端执行一次：

```sh
cd /Users/shenshen/.dotfiles
bash rime/tools/configure_notarization.sh
```

按提示输入开发者 Apple Account 和应用专用密码（不是账号登录密码，不发到聊天）；凭证验证后存入钥匙串，脚本自动配置 `.build/signing/release.json` 的 `notary_profile`。没有应用专用密码时，按 [Apple 官方说明](https://support.apple.com/102654) 创建。此配置仅在编译机器执行一次，安装使用电脑不需要。

配置成功后，按下面顺序执行完整编译、正式签名、公证和回归检查：

```sh
cd /Users/shenshen/.dotfiles
bash rime/tools/build_squirrel.sh
bash rime/tools/test_voice_preferences.sh
bash rime/tools/test_voice_hud.sh
python3 rime/tests/release_defaults_test.py rime/.build/squirrel/build/Build/Products/Release/Squirrel.app
open rime/dist
```

逐条执行，任一步报错先处理，不分发失败流程中的产物。`test_voice_hud.sh` 会在本机屏幕上短暂显示自己的测试浮条，不录音或操作其他应用。构建脚本会在末尾自动调用 `package_squirrel.sh`：先编译双架构组件，再使用 `.build/signing/release.json` 的身份签名应用及 PKG，随后自动提交 Apple 公证、等待 Accepted、装订票据并验证 Gatekeeper，无需手动再签名或重复打包。钥匙串若提示使用签名私钥，在系统窗口允许即可。

分发终端输出 `Release package:` 指向的 `rime/dist/Squirrel-版本.pkg`；该目录可能有旧包，以本轮输出路径为准。其他电脑只安装正式确认的 PKG；不强制退出登录或重启。当前安装连接问题仍在调查，组件 19/20 候选包已撤回，不应继续安装。不需要源码、Xcode 或签名证书。首次使用语音需要麦克风和辅助功能授权，并填写自己的豆包凭证。个人固定词条通过 dotfiles 另行同步，PKG 不携带这些词条，更新仍保留目标电脑的本地词库。

2026-10-16 已改为需要公证：必须看到 `PASS: notarization accepted, ticket stapled and Gatekeeper validation passed` 才作为已公证包分发。未配置 `notary_profile` 时正式打包会停止并提示先运行配置脚本，避免误分发仅签名的包。等待超时可按[签名与公证](signing.md)恢复同一提交，不必重复完整构建。脚本不会替换本机已安装的输入法。若也要更新编译电脑，再单独执行 `bash rime/tools/install_squirrel.sh`。重新编译无需删除整个 `.build/`；其中的本机签名配置未进入 Git，删除后默认打包可能退回开发临时签名。其他电脑若也要作为编译机器，需先按[签名与公证](signing.md)准备证书、私钥和本机配置，不能仅靠拉取 dotfiles 获得签名身份。

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
rime/dist/Squirrel-版本.pkg
```

本机开发构建可使用 ad hoc 签名，不需要付费开发者账户。正式发布包使用 Developer ID Application／Installer 签名，需要本机钥匙串中有配套私钥；配置见[签名与公证](signing.md)。2026-10-16 本机已配置公证认证，`Squirrel-20261016.041022.pkg` 已通过 Apple Accepted、票据装订和 Gatekeeper 验证。以后新生成的包仍需分别完成这三个步骤，不能继承旧包的公证结果。

默认复现本文版本。若将来需要测试不同提交，可以显式指定，固定版本更便于定位回归：

```sh
SQUIRREL_REF=master bash rime/tools/build_squirrel.sh
```

构建目录中若有手工修改，脚本会停止，避免覆盖源码改动。

## 安装到这台电脑

### 其他电脑直接使用已编译的安装包

现在发布的是单个 `rime/dist/Squirrel-版本.pkg`。复制到其他电脑，双击安装即可，安装器会尝试只重启输入法，无需强制退出登录；包内包含默认方案、公共词库、原生组件和可分发的语音默认设置，无需手动导入配置、运行迁移脚本或在目标电脑安装构建工具。详细操作见[单个 PKG 安装与更新](migrate-mac.md)。

安装脚本只刷新正式安装路径的 Launch Services 注册，使用系统 TIS API 注册和启用输入源，并重启该用户的输入法菜单/切换器。启用可能触发系统“允许启用鼠须管”确认框；API 返回成功不代表用户已完成确认。安装器不再直接写入 `AppleEnabledInputSources`，也不再程序化切换输入源。安装结束后如需切换，请使用系统菜单或原生切换快捷键。

macOS 26 的程序化切入可能出现“API 选中成功但 IMK 未激活、菜单空白”，上游仍有相关报告：[squirrel #1162](https://github.com/rime/squirrel/issues/1162)。构建副本被登记是另一项独立风险：打包阶段改用 `rime_deployer --build` 编译公共数据，避免执行临时 `Squirrel.app` 的通知/UI 入口。开发机清理旧构建副本注册时只撤销已确认的构建/验包路径，不删除正式输入法或重置系统授权。


更新安装只替换应用并修复必要的系统输入源登记，不写 `~/Library/Rime`、语音设置偏好或钥匙串；本地自定义词、学习词库、热词勾选、配置改动和已保存设置继续保留。由旧临时签名首次切换到正式签名时可能需要重新授权或保存 Key；同身份的正式更新通常可以继承权限，安装器不会删除凭证。

发布资源来自仓库 `rime/distribution/data/`、项目 YAML／Lua 和 `VoiceDefaults.plist`，不从当前用户目录采集。原生改动运行 `build_squirrel.sh`；只改默认资源且已编译过可运行 `package_squirrel.sh`。定制版采用 PKG 更新，关闭上游官方包的自动更新。

### 本机使用安装脚本

完成编译后，在仓库根目录执行：

```sh
bash rime/tools/install_squirrel.sh
```

脚本先备份当前 `/Library/Input Methods/Squirrel.app`，退出正在运行的鼠须管，再备份 `~/Library/Rime`。备份位于 `rime/.build/backups/日期时间.随机后缀/`，包含 `Squirrel.app` 和 `Rime`。新版脚本也将配置文件的符号链接转换成备份目录中的独立文件，避免仓库后续修改使备份内容一起变化。`original.txt` 指向第一次备份，`latest.txt` 指向最近一次备份。

随后 macOS 会显示自己的管理员认证框。密码只在系统认证框输入，脚本不读取或保存密码。安装使用 Apple 的 `installer`，不会更改整个 `/Library/Input Methods` 目录的所有者。

安装结束后，脚本验证应用签名，核对可执行文件、云插件、语音库及录音助手与构建产物相同，并输出源码提交号。文件一致不代表桌面输入连接正常。此前恢复 RequireLogout 的决定已撤回；不强制退出登录、不自动注销。当前调查中的升级脚本避免在 PackageKit 尚未完成注册时再次注册/启用输入源、写偏好或重启菜单；尚未通过受控安装对照，不能宣称解决了安装连接根因。

如果其他电脑尚未启用鼠须管，可在系统设置的键盘输入源中添加它。

## Apple 本地语音

语音功能不需要改个人 YAML。设置中可选择 Apple 本地或[豆包二遍识别](doubao-speech.md)，豆包凭证存入钥匙串。输入法菜单的“语音设置…”可以选择麦克风设备并测试音量；听写时显示动态波形浮条。默认轻按或按住 `Option` 启动，再按一次结束；快捷键支持单独的左右修饰键。输入法菜单单独提供“用户词典…”和“听写历史…”；语音设置保留中英文空格开关和豆包停顿容忍。先在设置页授予麦克风和辅助功能权限（无需额外授予输入监控）。跨应用切换后录音继续并显示浮窗预览，结束时无可编辑焦点则在同一黑色浮条中编辑和复制结果；没有独立结果窗口。运行需要 macOS 26、支持新识别引擎的设备和本地中文模型；其他电脑的权限和模型独立配置。操作、手动编辑保护与测试方法见 [Apple 本地语音输入](voice-input.md)。当前源码记录为 `VoiceInputVersion=17`、`SharedUserDictionary=true`、`MixedTextSpacing=true`、`SideSpecificModifierShortcut=true`、`VoiceUndoEnabled=false`、`GlobalDictation=true` 和 `DoubaoSpeechTwoPass=true`。

## 配置五笔与拼音路由

新版 PKG 已包含五笔、拼音反查、白霜词库和混输路由，新电脑无需额外安装词库或链接仓库。旧电脑的用户目录若存在同名配置，会继续优先于包内默认值；需要自行合并更新或备份后移走过期覆盖配置，再重新部署。以下链接方式仅供源码配置维护者使用。个人词典 `rime/custom_phrase.txt` 通过 dotfiles 和 Git 同步；本机 `~/Library/Rime/custom_phrase.txt` 链接到该文件，编辑器保存时保留链接。新电脑可按下面的源码配置链接方式启用个人词典。PKG 仍只带空白个人词典模板，不携带这些词条。

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

### 听写历史（24 小时）

“右上角输入法菜单 → 听写历史”查看最近的识别文字，按会话合并实时修订，包含已完成、已上屏和按 Esc 取消的听写。选择条目后可复制全文、选择部分文字复制、删除该条或清空历史。记录保存的是识别结果，不包含后续手动修改；无识别文字与自动验收音频不产生历史。Esc 仍立即关闭浮条，但不会删除已经保存的历史。

历史存放在 `~/Library/Application Support/Squirrel/VoiceHistory/history.json`，目录权限 0700、文件 0600，排除 Time Machine 备份，不保存音频，不额外上传到云端，也不进入 dotfiles 或 PKG。每条以最后更新时间保留 24 小时；输入法运行时每分钟清理，并在启动及读取历史时再次删除过期记录。输入法退出期间无法运行清理，下一次启动时清理。删除是本地文件删除，不承诺对磁盘或第三方备份做安全擦除。升级之前未保存的已取消听写，无法由新功能追溯恢复。

### 2026-10-17 安装注册排查记录

旧流程存在两项已修正的风险：构建/打包阶段执行临时 `Squirrel.app --build`（该入口发送系统通知），以及安装器直接补写 `AppleEnabledInputSources` 并程序化选择输入源。现使用不依赖输入法 UI 的 `rime_deployer`，只通过系统 API 注册/启用，保留系统原生切换流程。历史遗留构建副本已在开发机撤销注册；这不等同于证明全部菜单问题由此引起。

新增真实 macOS 回归检查：`python3 rime/tests/release_registration_test.py /绝对路径/Squirrel.app`。它在两个独立暂存目录编译数据，并逐次核对 Launch Services 中鼠须管的注册完全不变；异常时只撤销测试目录自己的注册。2026-10-17 已通过，公共默认数据、词库保留及安装策略检查也通过。原生 AppKit 文本框确认启用列表包含鼠须管与豆包，当前源为 `im.rime.inputmethod.Squirrel.Hans`。Carbon-only 命令行探针曾与原生输入上下文给出不同列表，不能单独作为桌面验收依据。

修复包 `Squirrel-20261017.054603.pkg` 已签名、公证并核对包内脚本。用户最初确认中文输入恢复但菜单仍缺项；随后通过系统设置重加唯一的原生条目，并撤销旧安装器补写的一条遗留偏好记录，原生查询由两个同名模式变为一个，用户已确认右上角菜单出现鼠须管且可切换。完整升级验收不能仅根据 API、编译或公证结果判断。后续验收需检查系统启用列表无重复、原生菜单可切换、五笔/拼音候选、菜单词典/历史入口，以及 Codex 持续听写和手动编辑保护。


遗留条目迁移：新版安装后及输入法启动时，只有在原生查询确认同一鼠须管简体模式存在至少两份启用引用，且旧偏好列表恰好有一条匹配旧安装器写入格式的记录时，才备份并移除该旧记录。不会移除唯一启用的输入源，不处理格式不明或多条旧记录的状态，不新增输入源偏好。系统稍后批准启用时也会重新检查。备份位于 `~/Library/Application Support/Squirrel/InstallationBackups/LegacyEnabledInputSources.plist`，目录 0700、文件 0600；备份或同步失败时不继续迁移/回退原数组。内存偏好隔离测试命令：`bash rime/tools/test_input_source_migration.sh`，覆盖唯一源保护、其他输入法保留、重复运行、备份失败和同步回退，不修改真实系统偏好。

含上述受限迁移的分发包为 `rime/dist/Squirrel-20261017.060604.pkg`，已通过签名、公证、staple/Gatekeeper 与最终包内脚本/功能标志核对。本机已通过原生设置修复并由用户确认菜单可切换，因此没有为验证新包而再次安装。


2026-10-17 语音修正包：`rime/dist/Squirrel-20261017.062115.pkg`（语音组件 18），已完成 Developer ID 签名、Apple 公证、票据装订和 Gatekeeper 检查。修正终端式起始光标、原生相对提交坐标、短暂输入控制器重建和结束时重复重放；见 voice-input.md。完整离线回归、独立浮窗 GUI 测试、最终包默认数据／用户词库保留、输入源迁移、安装策略及两次数据构建不改变真实输入法注册的检查均通过。尚未安装到本机，实际 Atom/Cloud Code 与 Codex 持续听写需在安装后验收；协议模拟通过不能代替桌面验收。


### 2026-10-17 热升级回归后的修正

`20261017.062115` 安装后，用户报告菜单再次缺项、所有语音只进入浮条。安装日志确认包已更新，TIS 仍将鼠须管报告为唯一启用模式，但系统输入源当时为豆包，语音原生连接没有激活。不能将“已启用”或“签名/公证成功”作为桌面可用的证据，也不能直接归咎于上游。上游有相关的 [macOS 26 激活问题](https://github.com/rime/squirrel/issues/1162)，触发路径与本次并不完全相同。

后续包恢复退出登录要求；升级不再执行输入源注册/启用/遗留偏好迁移，也不主动重启菜单。运行中的应用不再自动修改 HIToolbox 偏好。首次安装才注册/启用输入源。旧的 `--repair-input-source` 仅留作显式开发诊断，不由启动或安装流程调用。不要为“测试成功”而自动注销用户。

语音组件 19 新增辅助功能的安全实时写入后备路径：未取得原生 IMK 连接时，在已有辅助功能授权且宿主允许精确范围读写的条件下，使用自己的文字和光标校验进行修订。没有额外权限要求、剪贴板写入或模拟粘贴；不能精确确认时仍保留浮条，禁止自动重放。此路径还须经过已安装应用的真实桌面验收；模拟编辑、窗口测试或公证不能代替它。

修正包候选：`rime/dist/Squirrel-20261017.063732.pkg`，已签名、公证、装订并通过 Gatekeeper；最终包确认语音组件 19 与 RequireLogout。尚未安装本机，不能标记为真实桌面验收通过。本机通过原生系统设置重加条目后，用户已确认菜单恢复；固定音频测试未在草稿中得到文字，随后已停止测试、还原提供方及 fixture 设置，未改密钥。需继续核对已恢复输入源下的真实听写。


2026-10-17 用户真实桌面复验：通过系统设置重加唯一的鼠须管输入源、恢复菜单切换后，用户在 Codex 空白输入框确认选中鼠须管，反馈“能持续上屏，停止后没有重复”。此时本机仍安装 `20261017.062115`（语音组件 18），没有安装组件 19 候选包。因此，本轮“全部直接进入黑条”至少与升级后输入源未正常连接有关；已安装组件 18 的 Codex 持续上屏及停止无重复已获用户确认。此结果不覆盖 Atom/iTerm，也不证明组件 19 的辅助功能后备路径通过桌面验收。

本机维持当前可用版本，不为更新安装策略或验证候选功能而再次替换。组件 19 候选包 `Squirrel-20261017.063732.pkg` 已签名、公证，但仍未安装/通过真实桌面验收。后续升级须区分：包内与协议测试通过、安装后输入源在原生菜单可见并可切换、实际应用持续上屏与手动编辑保护；缺任一项不可宣称完整验收通过。安装策略仍使用明确的退出登录要求，不能凭本次手动修复承诺可靠热升级。


### 2026-10-17：iTerm2 停顿提交后的网格光标

用户确认 Codex 正常，但 iTerm2 的第一段有下划线、停顿提交后后续语音进入浮条。实际日志原因是 `write-unconfirmed`，并非切换焦点：例如 `selected=5074:0, expected=5058:8`，另有 `selected=5190:0, expected=5098:46`。iTerm2 的 [PTYTextView 实现](https://github.com/gnachman/iTerm2/blob/master/sources/TerminalView/PTYTextView.m) 将 selectedRange/markedRange 的位置映射为终端网格坐标，提交后的字符占用列数不能与 UTF-16 长度直接比较。

语音组件 20 只对 bundle ID `com.googlecode.iterm2` 启用网格提交确认：先前组字必须已经验证属于本次听写，提交后标记必须消失，光标必须有效且无选区，并经过现有异步确认等待、期间没有手动编辑撤销所有权。下一段以宿主实际标记范围重新定位，不自行猜测宽字符/emoji 列数。其他应用的坐标校验不变；没有先前组字证明的最终写入不会因此被放行，也不重复插入。

回归测试覆盖 12 次停顿/续说、中文和 emoji、手动 `[KEEP]`、后续语音，以及无先前组字证明时拒绝放行。本轮尚不等同于实际 iTerm2 桌面验收；不要向正在工作的 shell/Claude 会话自动输入测试文字或回车。

组件 20 修正包：`rime/dist/Squirrel-20261017.065108.pkg`，Developer ID 签名、Apple 公证、票据装订及 Gatekeeper 检查均通过。最终包元数据/脚本、公开默认数据及词库保留检查通过；尚未安装本机，实际 iTerm2 停顿续说和手动编辑保护验收待完成。安装后保存工作并退出登录、重新登录，再在独立空白输入位置验收，不要在工作 shell 中自动发送测试输入。


### 安装失效调查：已证实与待验证（2026-10-17）

本机仍为 `20261017.062115` / 组件 18，本轮没有重新安装、注销、重置权限或更改输入源列表。用户已确认重新添加原生输入源后菜单可用，Codex 持续上屏、停止无重复。iTerm2 坐标修复保留；未安装的 AX 实时写入、额外按键回调已撤掉，不改变现有上屏路径。

当次安装日志与统一日志可重建以下顺序：

| 本地时间 | 事实 |
| --- | --- |
| 14:25:27.799–27.803 | 旧进程 74620 正常退出，非未退出/双进程证据 |
| 14:25:30 | PackageKit 原子替换应用；postinstall 强制 LS 刷新并再次 TIS 注册；CLI 输出“Registered input source”，下一进程又输出“already enabled Hans” |
| 14:25:32.537 | postinstall 提前启动新进程 80095 |
| 14:25:32.577 | 脚本杀掉的菜单进程重新启动为 80098 |
| 14:25:32.629 | 新进程报告 `Failed to get unit 21828 from store`，对应 LS 记录失效；最近五小时该错误只检索到这一条 |
| 14:25:32.695 | 新菜单读取输入源，此时 PackageKit 尚未完成其最终注册 |
| 14:25:33 | PackageKit/Installer 完成自己的应用及子应用注册 |
| 14:25:35.356、36.858 | 新进程收到 IMK Activate Server；不能把故障概括为 IMK 从未启动 |

已证实的安装缺陷：把实时 TIS 枚举结果当作可靠的“是否已安装”判断，在升级窗口再次注册；在 PackageKit 最终登记前主动启动后端并重启菜单，使它们面对仍变化的应用记录。此时 API 返回启用不能证明菜单连接成立。没有证据证明此次遗留偏好迁移实际执行；其默认备份文件不存在，不能凭代码存在就将其认定为原因。

尚未证明：重复 TIS 注册、`lsregister -f`、提前启动、重启菜单中哪一个（或哪种组合）是缺项的充分/必要条件；一次 LS unit 错误也不能单独证明因果。当前证据支持注册/缓存时序竞态，但不能写成“根因完全查清”。不把历史构建副本或上游 macOS 26 问题当作本次的既定解释。

已取消 RequireLogout 与强制重新登录提示；升级 postinstall 保留既有注册、不改偏好、不杀菜单、不在事务中主动启动后端。此为待对照的最小安装修正，不视作已完成桌面验收。仅凭脚本测试不能证明菜单正常。下一步需要在可回滚、具备原生菜单/中文输入验收的环境中，对原脚本与最小脚本做受控升级对照，并记录安装前后输入源、菜单、实际连接和时间线；当前可用工作环境不作为反复试错对象。


用户授权的最小范围安装测试包：`rime/dist/Squirrel-20261017.070642.pkg`。重新编译收紧范围后的语音组件，撤去未安装的 AX 实时写入扩展，保留 iTerm2 网格提交修复；不强制退出登录/重启，升级脚本不重复注册输入源、不杀菜单。最终包范围、脚本、词库保留检查及 Developer ID 签名、Apple 公证、装订/Gatekeeper 均通过。20261017.063732 / 065108 仍撤回。本机未自动安装，用户安装后的菜单/输入连接和 iTerm2 停顿续说验收待完成；不能据公证结果宣称安装根因已解决。安装前版本/进程/时间基线保存在 `.build/installation-test-20261017/before.json`。若菜单缺项，先保留现场，不立即删除重加或注销，便于核对时间线。


### 070642 受控安装复现：旧嫌疑未能解释全部故障

用户安装 `20261017.070642` 后再次报告菜单缺项。此包确实走升级早退分支（15:09:52 安装日志确认），没有额外 TIS/LS 注册、没有菜单重启，也没有自动遗留偏好迁移。PackageKit 于 15:09:53 完成自己的注册，新 Squirrel 进程 87765 于 15:09:55 才启动，随后收到 IMK Activate Server。这次没有复现上次的 `Failed to get unit` 错误。因此，不能再将上述自定义 postinstall 动作、提前启动或单次 LS unit 错误当作缺项的必要根因；取消它们尚未解决故障。

保留现场检查：已安装版本正确，简体模式可见标志为 true，TIS 枚举一份启用且选中的 Hans；主输入法应用在 LS 中只注册一个标准路径。`com.apple.inputsources.plist` 的 `AppleEnabledThirdPartyInputSources` 仍完整包含豆包与鼠须管模式/父项，只有标识字符串，没有文件书签；不能凭原子替换就宣称偏好中存在旧文件引用。旧 `com.apple.HIToolbox` 不是完整第三方启用列表。

已保存 `.build/installation-test-20261017/failure-070642.json` 和对应系统时间线。随后进行单变量实验：只停止当前用户 TextInputMenuAgent（81474，新进程 88024），鼠须管 PID 87765 与第三方输入源偏好文件 SHA-256 均保持不变，没有删除重加输入源、重启后端或重置权限。原生菜单结果等待用户确认，不能用新进程存在替代可见性验收。

用户确认仅重启 TextInputMenuAgent 后仍缺项，因此不能把问题归为该进程单独持有的旧列表。后续对 TextInputSwitcher 做独立实验：普通 SIGTERM 无效（原 PID 14201 仍在），未将该请求误记为完成重启；确认 UID 501 后仅停止该 PID，再通过 `gui/501/com.apple.TextInputSwitcher` 启动，新 PID 88875。鼠须管 PID 87765 和第三方输入源偏好散列保持不变，菜单结果待用户确认。全过程未删除重加输入源或重新安装。

用户确认 TextInputSwitcher 真正重启后仍缺项；两个界面进程的独立重启均未恢复。进一步只读检查：已安装应用深度签名校验通过，Hans 图标 URL 指向标准安装路径且可读，模式可见标志为 true。无窗口、无激活的 AppKit 输入上下文和 Carbon 查询均包含 Hans 与父输入源，当前源为 Hans。父输入源图标 URL 为 nil；与豆包相比缺少 `tsInputMethodIconFileKey`，但没有因果证据，未修改图标/Info.plist/签名。尝试通过桌面工具读取 ControlCenter 系统菜单超时，因此不能据 API 列表宣称实际菜单正常；需要菜单展开截图核对可见结构。此轮未改输入源配置、未重装或重启鼠须管。

截图确认菜单只有 ABC/豆包，鼠须管整项缺失。对标准安装路径调用一次真正的 TISRegisterInputSource（不是 enabledModes 早退 CLI）返回 0，来源无重复，进程和第三方输入源偏好散列不变；用户确认仍缺项。随后仅对 Hans 执行官方禁用/重新启用，用户截图仍缺项，当前源切到 ABC；未程序化选择。

进一步仅对父输入源做官方禁用/恢复启用并保留原模式集。API 返回 0 后立即读取现代偏好时，两条鼠须管记录尚未写回；准备撤销时并发保护拒绝了写入，再次只读确认系统已延迟写回完整原始记录，与实验前逐项一致。因此 defaults import 实际未执行，不应把这个瞬时差异误报为永久丢失或 API 无法持久恢复。父源实验完成后的原生菜单结果待确认。父源图标依旧 nil，未改 Info.plist。

只读核对本机 pkgbuild 官方手册：BundleOverwriteAction=upgrade 原子替换整个 bundle；update 保留旧路径并覆盖文件，但缺少现有应用时不会安装，且保留包中已不存在的旧文件。因此不能简单换成 update 就宣称仍支持同一个首次安装/升级包，更不能在尚未验证因果时顺手改变发布策略。


### 父输入源恢复实验通过（用户真实确认）

用户确认鼠须管父输入源启停完成、现代偏好恢复原样后，菜单“出现了，可以切换”。在本次现场的对照序列中，单独重启菜单代理、重启切换进程、重新 TIS 注册、仅启停 Hans 均无效；最后对父源执行官方禁用/重新启用并保留原模式集合后恢复。配置内容与实验前完全一致；未重启鼠须管、改签名或图标；准备做的 defaults import 被保护检查拦截，实际没有执行。

已确认的故障层与恢复动作：升级后父输入源启用状态需要重新建立，单独恢复子模式不够。不能据此断言 Apple 私有缓存的具体实现、原子目录替换必然是根因，或仅凭一次成功就保证自动化升级修复可靠；此前的 LS 竞态、缺父源图标均不能直接当作本次必要原因。后续若实现安装恢复，只能在安装事务结束后针对原已启用的鼠须管父源、保留原模式集合，等待异步偏好状态稳定，并单独做真实升级验收；不要在 postinstall 中立即重试或每次启动无条件切换。当前工作环境已恢复，不再重装。


2026-10-17 用户真实 iTerm2 验收通过：已安装 `20261017.070642`，在菜单通过父输入源启停恢复后，用户说第一句、停顿两三秒提交，再继续说第二句，反馈“两段都上屏，没有转黑条”。这验证了当前包的 iTerm2 停顿提交衔接修复；本轮没有自动发送测试文字或回车。当前可用环境保持不动。安装后父输入源自动恢复尚未实现/通过升级验收，与此次 iTerm2 功能验收分别记录。


### 安装后一次性父输入源恢复（验收中）

当前恢复辅助程序 `Contents/Helpers/SourceRecovery` 使用 Carbon 官方启停 API，只处理原已启用的鼠须管父输入源并恢复原简体／繁体模式集合。postinstall 只安排任务，不立即启停；任务等待安装器退出、新安装收据版本匹配且连续稳定两秒。状态保存在 `~/Library/Application Support/Squirrel/InstallationRecovery/state.json`，不含词典、音频或密钥。辅助程序不选择输入源、不写系统输入源偏好、不重置权限、不重启菜单或后台、不强制退出登录。

任务不放入 LaunchAgents，不随登录或输入法启动重复执行；版本和安装目录 inode 标识本次安装，已完成的同次安装不重复恢复。等待超过五分钟则不改输入源，状态记为 deferred；安装器需在此时间内关闭。用户禁用／移除输入源或改变模式集合时跳过恢复，不擅自重新启用。部分 API 调用报错会尽力重新启用父源并恢复原模式，记录失败供排查。

验证：`bash rime/tools/test_source_recovery.sh` 检查安装事务等待条件、原模式集合保持、失败后的恢复路径；不能替代真实菜单验收。本机升级自动执行结果另行记录。

本轮本机候选为 `20261017.093837`：实际展开包确认签名有效，语音组件仍为 20，前端与语音二进制 UUID 与已验收的 070642 完全一致；新增恢复辅助程序版本 1。公证因钥匙串 profile `squirrel-notary` 暂不可用未完成，此包仅用于已授权的本机升级试验，不能作为已公证发布包。安装前应用备份在 `.build/backups/20261017-before-automatic-recovery/Squirrel.app`。安装处于系统管理员认证等待中，尚未宣称自动恢复通过。

本机自动升级执行结果：用户完成管理员认证后，CLI installer 报告升级成功，安装收据和应用版本均为 `20261017.093837`。恢复任务自行从 running 进入 completed；原四条第三方输入源记录逐项保持一致，一次性 task.plist 已移除。系统信任服务环境下 codesign 深度严格校验通过。再次执行同次安装的 `SourceRecovery --prepare` 返回 already completed，没有重复启停。未做手动删除重加、菜单重启或退出登录。原生菜单可见、可切换和中文输入仍待用户确认；不将 completed 状态替代桌面验收。

### 一次性自动恢复：本机真实升级验收通过

2026-10-17，用户确认安装 `20261017.093837` 后“能看到、能切换，中文输入正常”。本轮由安装任务自动等待安装器退出后刷新父输入源，没有手动删除重加、重启菜单或退出登录；原输入源记录保留，同次安装重复调用被跳过。由此确认该恢复方案在本机本次真实升级有效，不代表其他电脑均已验证，也未证明 Apple 内部故障的全部原因。当前包正式签名已通过，公证因 `squirrel-notary` 凭证暂不可用尚未完成，不能作为已公证发布包分发。

最终分发更新：`20261017.093837` 已上传 Apple（提交 d40e2ad5-2839-462b-82dd-c566feb1728d）。账户 profile 的 info 查询暂不可用，但随后成功取得 Apple 公证票据并装订，stapler validate 通过，spctl 安装校验 accepted / Notarized Developer ID。因此本包公证验证已完成，先前“尚未公证”的状态已更新。分发包为 `dist/Squirrel-20261017.093837.pkg`，测试压缩包为 `dist/Squirrel-20261017.093837-test.zip`，内含同一装订后 PKG、测试说明和 SHA-256。压缩包完整性及内嵌 PKG 校验通过；其他电脑的真实验收仍待进行。


### 语音组件 21：去口水开关和手动重写

新增豆包 `enable_ddc` 开关，默认关闭、下轮听写生效；二／三级手动重写使用独立方舟 API Key 和模型 ID。录音时点黑条右侧重写图标先结束听写，再以本轮完整识别文本请求模型；历史也可选中记录重写。结果只在同一黑条上方预览、编辑和复制，用户自行替换，不改变宿主或原历史记录。普通完成仍关闭黑条，既有安装后一次性输入源恢复保持不变。配置和限制详见 `voice-input.md` 的“去口水与手动文字重写”。

离线重写 HTTP／提示词和错误处理、豆包协议及回环模拟、原生双屏浮条／历史入口、连续上屏和手动编辑保护回归已通过。真实文本模型效果与账号连通性仍需用户配置后验收，虚拟结果不代表真实云验收。

语音组件 21 安装包：`rime/dist/Squirrel-20261018.043528.pkg`。正式签名、Apple 公证、票据装订及 Gatekeeper 安装校验通过；实际展开包确认含语音组件 21、父输入源恢复 1 和新功能标记，且未包含个人词条、历史、文字模型配置或密钥。本轮未安装到当前输入法；真实云重写需安装并配置后验证。

申请引导补充包：`rime/dist/Squirrel-20261018.060000.pkg`。豆包语音与文字重写配置内新增常驻申请步骤、各自 Key 申请入口和官方接入指南；已完成实际提示区域渲染检查、双架构编译、正式签名、公证装订和 Gatekeeper 验证，并核对最终包内包含新入口。未自动安装。

黑条快捷键更新包：`rime/dist/Squirrel-20261018.064654.pkg`。点击黑条获得键盘焦点后，⌘T 轻整理（二级）、⌘R 重整理（三级）；显示黑条本身不会抢焦点。快捷键不在其他窗口生效，不重复处理长按或已有请求；星星按钮隐藏下拉箭头，保留点击选择菜单。原生窗口测试通过 AppKit 应用事件分发验证录音／结果状态的快捷键，同时验证焦点限制、复制关闭、过期结果拒绝和双屏位置；语音编辑保护回归通过。正式签名、公证、装订和 Gatekeeper 验证通过，实际包内二进制 UUID 与最终编译件一致。未自动安装到本机。

识别修复与加载动画包：`rime/dist/Squirrel-20261018.072033.pkg`。重新编译 arm64/x86_64 输入法及语音组件，兼容服务省略文本的空分句，零 PCM 停止直接取消，并增加不含正文的音频发送计数和时序诊断；重写请求期间显示旋转加载动画，成功／失败／关闭时停止。豆包协议／回环、原生黑条加载生命周期及重写模拟接口回归均通过。实际展开包确认双架构二进制 UUID 与本次编译一致、包含功能标记、恢复脚本未变，不含个人词库、历史或密钥。Apple 状态查询一次超时后，恢复同一提交 `7d19c6fd-5ca4-4518-9922-074c1ad19b7f`，最终 Accepted；正式签名、票据装订、Gatekeeper 和最终包哈希校验通过。未自动安装。45000002 的真实触发原因仍需借助新增诊断在实际使用中确认，不以模拟回归替代真实云验收。


iTerm2 键盘自动空格兼容包：`rime/dist/Squirrel-20261019.043737.pkg`。加入仅用于 iTerm2 的有界光标前文本读取回退，候选上屏与英文直输共用；不缓存前文，不猜测不可读文字，不改变安装恢复策略或用户词库。保留上一包豆包识别修复及重写加载动画。完整双架构编译、Developer ID 签名、Apple 公证（`478592cc-c65f-4e37-a365-463f4b0d7276`）、装订和 Gatekeeper 检查通过；展开最终 PKG 核对本次二进制 UUID、功能标记、原安装脚本及空个人词库模板，装订后文件哈希与 Accepted 记录一致。自动空格与既有输入保护回归通过；本机未自动安装，iTerm2 实际问题是否解决由用户在独立位置复测确认，不能以公证或模拟测试替代。


临时键盘诊断包：`rime/dist/Squirrel-20261019.044425.pkg`，公证提交 `34b1547d-14bd-44e6-aedc-446ef600c5d4` Accepted，装订及 Gatekeeper 验证通过。默认关闭、开启后限时限量的 iTerm2 路径元数据日志用于排查 043737 未解决的自动空格问题；不记录按键字符或正文，不代表问题已经修复。工具用法见 voice-input.md。尚未自动安装。


真实追踪后的 iTerm2 修正版：`rime/dist/Squirrel-20261019.045632.pkg`。终端接口把前文返回为填充空白，英文输入虽经过处理却未加空格。现由同一输入控制器管理短尾文，按实际格坐标连续性补新输入间隔，未知宽度／手动编辑／客户端变化撤销；不以缓存授权删除已有文本。前端与双架构桥重新编译，完整输入回归、原生 IMK 重放、正式签名、公证、装订、Gatekeeper 和最终哈希检查通过。安装恢复与私有词库策略未变。045442 为过程候选，不交付；最终 045632 尚待用户安装并验收。


用户验收 045632 的 Shift 直输路径已通过，中文组字下回车原样上屏仍缺间隔。补修包 `rime/dist/Squirrel-20261019.050349.pkg` 仅允许已有组字时 Return／数字键盘 Enter 保留衔接记录；非组字回车继续清空。新增原生用例从失败到通过；双架构组件、正式签名、公证、装订、Gatekeeper、展开包二进制及最终哈希验证通过。未自动安装，回车路径真实验收待用户完成。

2026-10-19 最终验收：用户安装 `Squirrel-20261019.050349.pkg` 后确认中文组字中回车提交 mac 得到“中文 mac，空格正常”；此前 Shift 切英文直输也已通过。两条目标路径实际 iTerm2 验收完成，当前安装保持不动，诊断关闭。
