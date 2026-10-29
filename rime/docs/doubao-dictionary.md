# 豆包词库：只读导入与推送到 Mac 豆包

这是**两个单向功能**，不是云端双向同步，也不是豆包/鼠须管 userdb 的直接复制：

1. 从 Mac 豆包已下载的侧词库预览、搜索、选择，合并到 Rime 自定义词典草稿。
2. 把选中的 Rime 固定短语写入 Mac 豆包的本地学习词库，再由豆包自己按调度上传到 iPhone。

两者都只操作本机豆包文件；不调用豆包私有云 CRUD，不删除云端词，不同步 Rime 学习 userdb。

## 1. 从豆包导入

入口：鼠须管菜单 → **用户词典** → **从豆包合并…**。

- 纯 Swift 只读解析已下载的侧词库，不加载豆包私有框架，不需要豆包 API Key 或额外系统权限。
- 支持搜索、多选、全选当前结果；选择只是加入编辑草稿，必须在主词典页“保存并部署”才写入。
- 不修改豆包侧词库、账号目录或云端。
- 解析器校验树结构、长度、头/扩展版本、UTF 编码和条目数；未知格式、损坏文件或多个账号歧义时拒绝导入。当前适配的侧词库格式按实现固定的版本/魔数判断，升级豆包后先重新验证。

合并规则：

- 新词使用豆包原记录的拼音编码，权重 1；不改写为五笔编码。合并后可在主词典修改。
- 相同词条保留本地格式、编码、权重、语音别名和热词选择；与手工词同编码的豆包词不抢占手工词；大小写/空白归一后相同的词保留本地写法。
- 新增词默认关闭“语音热词”，不随请求发送。
- 删除已导入词后保存会生成本地排除记录；这是本地排除，不是删除豆包云端。之后可重新导入其他词。
- 导入来源和排除记录保存在本机 `mixed_user_dictionary.json`，不进入 Git/PKG；排除只存来源哈希，不保留被删词明文。

## 2. 推送到豆包

入口：用户词典窗口 → **推送到豆包…**。

- 只推送 `custom_phrase.txt` 的固定短语；Rime 学习 userdb 不推送。
- 汉字词、带有效拼音编码的英文/邮箱词（例如 `yangyu445` 挂到 `yang yu`）可推送；无法识别为拼音的编码会标记失败。
- 预览表显示词/拼音/来源/状态；默认选中可添加词，用户二次确认后才写入。
- helper 先写入豆包本地学习词库 `usr.dat`，退出豆包、备份原文件、校验后原子替换；不写侧词库、同步状态或账号其他文件。
- 写入后需要用户切回豆包并正常输入一次中文，让引擎按自身调度上传；iPhone 端按自己的调度拉取，公开测试词通常约 1–2 小时，最长可能更久。恢复 Mac 本地备份不会删除已上传云端副本。
- Mac 豆包当前可能是 86 五笔模式，新词是拼音学习词；Mac 候选不一定立即出现，最终以 iPhone 拼音候选为准。
- 选中的词经豆包账号上传；预览/确认页必须明确提示。不要用它推送敏感/私人内容。

### helper

`native/doubao-dictionary/doubao_push.cpp` 是独立可执行文件，固定校验豆包引擎 SHA-256；豆包升级后拒绝写入，需要重新运行：

```sh
bash rime/tools/build_doubao_push.sh
```

helper 安装到 `~/Library/Application Support/Squirrel/DoubaoPush/doubao_push`，ad-hoc 签名且不带 hardened runtime，因此可以 `dlopen` 厂商框架；它不进入 Squirrel.app、PKG 或正式签名流程。`build_squirrel.sh` 检测到豆包引擎时会尝试构建；失败只警告。

## 3. 边界与隐私

- 导入是只读本机豆包数据，不联网、不需要 Keychain。
- 推送只写本机豆包 `usr.dat`；豆包自己负责上传，Squirrel 不读取/导出账号 Token。
- 不实现豆包云端删除、批量改写、Rime 学习词推送或 Mac/iPhone 双向合并。
- 备份位于 `~/Library/Application Support/Squirrel/DoubaoPush/backups/`，属于私人数据，不要提交或发到聊天。
- 模拟/合成词库测试通过不等于真实 iPhone 已收到；最终以实际候选为准。

## 4. 测试

```sh
bash rime/tools/test_voice_preferences.sh
python3 rime/tests/verify_doubao_import.py "/Library/Input Methods/Squirrel.app"
bash rime/tools/build_doubao_push.sh   # 构建、selftest、安装
```

`verify_doubao_import.py` 使用隔离 librime 用户目录和合成短语，验证导入拼音词在混合五笔方案中的首选/提交。helper selftest 只在临时目录验证 Add/Save/Reload、重复 Add、拼音分段、长度、备份/原子替换和上传控制流，不读取真实账号。真实推送/iPhone 验收需人工。
