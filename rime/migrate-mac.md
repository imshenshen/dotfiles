# 单个 PKG 安装与更新

其他电脑只需复制 `rime/dist/Squirrel-版本.pkg`，双击安装，完成后退出登录再重新登录。无需复制配置目录、运行迁移脚本或安装 Xcode。首次使用时，若系统未自动启用，在「系统设置 → 键盘 → 文本输入」中添加鼠须管。

安装包包含五笔／拼音混输、白霜等公共词库、第五码顶字、云候选、语音组件、界面设置，以及当前发布的右 Option、豆包二遍、自动空格和停顿默认值。

每台电脑首次使用语音仍需授予麦克风、输入监控和辅助功能权限，并在语音设置中保存自己的豆包凭证。麦克风默认跟随该电脑系统设置。Apple 本地识别需要 macOS 26 和兼容模型；豆包组件最低部署目标是 macOS 13；安装包同时包含 arm64 和 x86_64。

## 更新保留哪些数据

以后直接安装新版本 PKG，然后退出登录再登录。安装器只更新 `/Library/Input Methods/Squirrel.app`，不会删除、搬动、复制或覆盖 `~/Library/Rime`、用户偏好及钥匙串。

因此以下内容始终留在目标电脑本地：

- 自定义词条 `custom_phrase.txt`、词典元数据／热词勾选 `mixed_user_dictionary.json`。
- 五笔、拼音和云候选的学习词库 `*.userdb`，同步记录及机器身份。
- 用户自行修改的 YAML／Lua 配置。
- 麦克风选择、快捷键、空格开关、停顿等已保存的语音偏好。
- 豆包 API Key、Access Token、App ID 等账户信息。

应用内的 SharedSupport 是公共默认配置；`~/Library/Rime` 是个人配置层，同名本地文件优先。新安装包会更新默认配置，个人改动继续覆盖默认值。语音默认值通过 UserDefaults 的注册默认值加载，已有偏好不会被重置。

如果目标电脑已经有旧版自行复制的完整方案／词库，其同名文件也会覆盖包中的默认资源。无需删除学习词库；希望启用新的公共配置时，可自行备份并移走相应旧的方案文件。全新安装不需要此步骤。

正式发布流程已使用固定 Developer ID 签名；由旧临时签名首次迁移时，可能需要重新授权或保存同一个 API Key。同身份正式更新通常可以继承权限。当前按用户决定暂不提交 Apple 公证，安装仍可能受 Gatekeeper 限制；详见[签名与公证](signing.md)。

已移除输入法菜单中的“检查更新”及 Sparkle 更新入口。定制版本通过新 PKG 更新，不使用上游 Sparkle 官方包更新，以免替换掉定制语音和云候选组件。

## 在当前仓库生成发布包

原生代码有变化时，在安装完整 Xcode 等构建依赖的电脑上执行：

```sh
bash rime/tools/build_squirrel.sh
```

脚本编译并输出 `rime/dist/Squirrel-版本.pkg`。只修改发布默认配置／公共词库且已存在编译产物时，可直接重新打包：

```sh
bash rime/tools/package_squirrel.sh
```

每次自动生成递增的 UTC 时间版本号，包内应用版本和安装器版本一致。也可通过 `SQUIRREL_RELEASE_VERSION` 明确指定版本，但维护者应保证新版本递增。发布包被 Git 忽略，单独复制生成的 PKG 即可。

公共资源源码固化在 `rime/distribution/data/`，打包不读取当前电脑 `~/Library/Rime`。项目维护的四个 *.custom.yaml、wubi86_pinyin.schema.yaml 和 lua/wubi_pinyin_router.lua 直接来自 rime/ 源码。可分发语音默认值在 `rime/distribution/VoiceDefaults.plist`；个人词典、账号、设备和验收开关不得加入发布资源。

默认资源先在临时应用中编译，再签名和打包；安装时不修改签名资源，不写用户目录。旧的 `export_squirrel_migration.sh` 仅用于另行备份／迁移自己的个人资料，不属于发布或更新流程。

2026-10-14 发布修正：主程序与录音助手均包含 NSMicrophoneUsageDescription；源 Info.plist 和打包流程双重保证，发布测试检查最终包内权限说明。禁用额外的中英文状态栏项，保留系统输入源菜单。旧版本 20261014.072758 的首次麦克风授权崩溃由缺少说明引起，需安装修正包并退出登录再登录。

麦克风启动兼容修正：不再将所有音频引擎配置通知当作设备切换；相同设备和采样格式继续测试，停止的同格式引擎尝试恢复。真实断开、切换或格式改变仍停止；旧会话通知不影响新会话。


## 旧配置覆盖导致四字母拼音没有候选

若 `nihao` 和 `zzmima` 正常，而 `mima` 没有候选，检查 `~/Library/Rime/lua/wubi_pinyin_router.lua` 是否仍是“仅超过四字母才添加 smart_pinyin”的旧路由。用户目录的文件或指向旧 dotfiles 的符号链接会覆盖 PKG 内的新默认值；安装新版应用本身不会覆盖这层配置。

修复时先备份，再将当前应用 `Contents/SharedSupport` 内的 `wubi86.custom.yaml`、`wubi86_pinyin.schema.yaml`、`lua/wubi_pinyin_router.lua` 同步到实际配置位置（符号链接应更新其目标文件），然后重新部署。不要删除自定义词条、学习词库或整个 Rime 目录。部署后应出现 `build/wubi86_pinyin.prism.bin`，编译方案使用 `mixed_pinyin_translator@smart_pinyin` 和 `prism: wubi86_pinyin`。

2026-10-15 已在 jdmac 验证此情况；配置备份位于 `~/Library/Rime/config-backups/mixed-pinyin-20261015-163701/`。使用远端实际编译方案在隔离目录中验证 `mima → 密码`、`mimi → 秘密`、`nihao → 你好`、`zzmima → 密码`，五笔第五码顶字也通过。

显式 `SQUIRREL_ADHOC=1` 仅用于开发包，更新可能使旧系统授权失配，不应当作正式更新分发。
