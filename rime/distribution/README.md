# 发布默认资源

`data/` 是 2026-10-14 从现有部署中固化的公共方案资源快照（原始词库主要为 2024-12-20 安装版本），不是更新到最新白霜的操作。包含白霜、五笔、朙月拼音及其公开词库、Lua、OpenCC 资源；保留各文件已有的作者和来源信息。

来源：
- https://github.com/gaboolic/rime-frost （licenses/rime-frost-LICENSE）
- https://github.com/KyleBing/rime-wubi86-jidian （licenses/wubi86-LICENSE）
- https://github.com/rime/rime-luna-pinyin 及 Squirrel 预设资源（原有发行包授权文件仍随应用保留）

公共方案源文件在这里保存，以后打包不读取当前用户的 Library/Rime。项目维护的 *.custom.yaml、wubi86_pinyin.schema.yaml 和 wubi_pinyin_router.lua 仍由 rime/ 中的源文件覆盖，不在此处维护重复版本。

VoiceDefaults.plist 保存右 Option 快捷键、豆包识别资源、停顿和自动空格等可分发默认设置；运行时通过 UserDefaults.register 注册，已有设置优先。禁止包含 App ID、密钥、麦克风 UID、验收开关或用户词典。

安装脚本只注册输入源和关闭旧进程，不复制或写入用户数据目录。所有默认资源属于应用包；用户本地同名配置由 Rime 的用户配置层覆盖。
