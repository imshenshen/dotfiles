# 在 macOS 编译和安装新版鼠须管

稳定版更新通道目前提供 Squirrel 1.1.2，但上游主分支已加入云候选所需的 `_refresh_ui` 协议。本文编译上游前端并添加本仓库的云候选原生插件，不需要 fork 鼠须管。上游源码的版本号仍为 1.1.2，因此这里用源码提交号识别构建，不能只看输入法的版本数字。

## 编译版本与依赖

本文脚本默认固定到已验证的上游提交 `0cd71a6130a5866b0ae6ba0494929ebdc8211194`。这次编译使用 macOS 26.5.1、Xcode 26.2、CMake 3.31.2，生成 Apple Silicon 和 Intel 双架构应用。

2026 年 10 月 8 日已在本机运行下述编译和安装流程。双架构、签名、源码记录和 `_refresh_ui` 检查均通过；隔离测试覆盖禁止自动上屏、第五码转拼音、退格恢复五笔、分段选词、光标编辑、`zhongguo` 完整拼音及 `zz` 反查。云插件通过模拟响应的异步引擎测试，以及搜狗和 Google 的公开样例实网测试。macOS 要求的退出登录与重新登录由用户在保存工作后完成。

编译的是 Squirrel 前端；librime 1.17.0、Lua 等插件和 Sparkle 2.6.2 使用上游发布的预编译二进制。这是[官方编译说明](https://github.com/rime/squirrel/blob/0cd71a6130a5866b0ae6ba0494929ebdc8211194/INSTALL.md)提供的依赖快捷方式，无需在本机重新编译 Boost 和整个 librime。依赖下载地址固定在该提交的 [action-install.sh](https://github.com/rime/squirrel/blob/0cd71a6130a5866b0ae6ba0494929ebdc8211194/action-install.sh) 中。

需要完整 Xcode，单独的 Command Line Tools 不够。先从 App Store 安装 Xcode 并启动一次，完成协议确认和组件安装。然后在终端检查：

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
2. 运行上游依赖下载脚本，获取官方二进制和默认方案。
3. 用 Xcode 编译 `arm64` 与 `x86_64` 前端，采用本机临时签名。
4. 从 Boost 官方 GitHub 下载并校验 1.89.0 头文件源码包，编译双架构云插件；不需要安装 Homebrew Boost 或启动额外服务。将插件和全部默认方案数据复制进应用包，并预先编译默认词典。
5. 写入源码提交记录，重新签名并验证整个应用包。
6. 制作安装包；安装脚本跳过预置数据的再次编译。

构建文件位于 `rime/.build/`，已经被 Git 忽略。默认脚本固定前端和二进制依赖版本；默认输入方案由 plum 获取，其词库内容可能随上游更新。

生成的文件：

```text
rime/.build/squirrel/build/Build/Products/Release/Squirrel.app
rime/.build/squirrel/package/Squirrel.pkg
```

不需要付费 Apple Developer 账户。这里的应用采用 ad hoc 签名，安装包没有 Developer ID 签名和公证；适合个人在自己的电脑上编译安装。复制到其他电脑时可能需要 macOS 的本地安全确认，另一台电脑重新编译也可以。

默认复现本文版本。若将来需要测试不同提交，可以显式指定，固定版本更便于定位回归：

```sh
SQUIRREL_REF=master bash rime/tools/build_squirrel.sh
```

构建目录中若有手工修改，脚本会停止，避免覆盖源码改动。

## 安装到这台电脑

完成编译后，在仓库根目录执行：

```sh
bash rime/tools/install_squirrel.sh
```

脚本先备份当前 `/Library/Input Methods/Squirrel.app`，退出正在运行的鼠须管，再备份 `~/Library/Rime`。备份位于 `rime/.build/backups/日期时间.随机后缀/`，包含 `Squirrel.app` 和 `Rime`。新版脚本也将配置文件的符号链接转换成备份目录中的独立文件，避免仓库后续修改使备份内容一起变化。`original.txt` 指向第一次备份，`latest.txt` 指向最近一次备份。

随后 macOS 会显示自己的管理员认证框。密码只在系统认证框输入，脚本不读取或保存密码。安装使用 Apple 的 `installer`，不会更改整个 `/Library/Input Methods` 目录的所有者。

安装结束后，脚本验证应用签名、核对安装后的可执行文件和云插件与构建产物相同、输出源码提交号，重启输入法并触发重新部署。显式重启是为了避免 macOS 在管理员认证期间自动启动旧进程、未加载新插件的情况。macOS 安装器要求退出登录后重新登录，以刷新输入法缓存；请保存其他应用的工作后自行操作，脚本不会自动退出登录。

如果其他电脑尚未启用鼠须管，可在系统设置的键盘输入源中添加它。

## 配置五笔与拼音路由

新编译的应用不会自动包含个人五笔配置。另一台电脑仍需安装五笔、拼音反查和白霜词库，并按仓库 README 的输入法安装步骤链接配置。

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

`LocalBuild.plist` 应包含 `CloudPinyinVersion = 1`。确认插件架构：

```sh
lipo -archs "/Library/Input Methods/Squirrel.app/Contents/Frameworks/rime-plugins/librime-cloud-pinyin.dylib"
```

切到五笔方案和中文模式，实际输入 `nihao`：前四码仍是五笔，第五码显示“你好”；空格确认，退格回四码恢复五笔。`zhongguo` 查询“中国”，`zznihao` 显式反查“你好”。停顿后云候选按本地、搜狗、Google 的轮次交错出现，注释显示来源。完整排序和服务开关见[云候选说明](cloud-research.md)。

## 编译流程中处理的两个问题

预置 Rime 数据必须在最终签名前编译。直接使用上游安装脚本时，它会在安装完成后新增 `SharedSupport/build` 文件，导致本地 ad hoc 签名校验失败。本文提前生成这些文件，再签名；打包时复制上游 postinstall，仅增加 `RIME_NO_PREBUILD=1`，保留注册和启用输入法的操作。

默认方案数据由脚本完整复制进应用，避免依赖上游生成 Xcode 资源列表的过程。这样 `quick5` 及其词典也会包含在安装包内。上述调整在本仓库的构建与打包脚本中完成，没有修改 Squirrel 输入处理源码。

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
