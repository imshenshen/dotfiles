# 词库自动同步（阿里云 OSS）

同步固定词条、语音别名、热词和 Rime 学习词库快照；凭证只在 Keychain。它解决多 Mac 的个人数据同步，不是实时协同，也不替代 Rime 自身的部署。

## 数据范围

上传到 OSS 的一个 AES-GCM 加密 bundle：

- `custom_phrase.txt`：固定短语、编码、权重
- `mixed_user_dictionary.json`：语音别名、豆包热词勾选、导入来源和排除墓碑
- `sync/<installation-id>/*.userdb.txt`：Rime 学习词库快照

不上传 `*.userdb` 原始 LevelDB、`installation.yaml`、`user.yaml`、听写历史、语音快捷键、Keychain 或 Git 配置。

学习词库不是直接复制运行中的 database；同步时先下载其他机器的快照到 `~/Library/Rime/sync/`，调用 Rime `sync_user_data()` 合并，再收集本机快照上传。每个 installation id 保留自己的快照，由 Rime 合并。

## 配置

输入法菜单 → **词库自动同步…**：

- endpoint 默认 `https://ss-storage-private.oss-cn-beijing.aliyuncs.com`
- bucket 默认 `ss-storage-private`
- prefix 必须以 `shurufa/` 开头，默认 `shurufa/rime-sync/v1`
- AccessKey ID / Secret 只保存到 Keychain（service `im.rime.inputmethod.Squirrel.RimeSync`，accounts `accessKeyID`/`accessKeySecret`）
- “测试连接”写入并读回 prefix 下固定 `_connection-test.bin`，不删除对象；只需 PUT + GET，不依赖 DELETE
- “立即同步”立即执行；自动同步在词典保存后、启动约 20 秒后、每 10 分钟触发；需要先点“保存”，仅测试连接不会保存凭证

两台机器使用同一 bucket/prefix 和同一 Secret。Secret 由 HKDF-SHA256 派生 AES key；更换 Secret 后旧远端 bundle 无法解密，必须先删除远端对象或明确重新初始化同步；本机词库不会因换 Secret 丢失。

## 加密与并发

- bundle 使用 AES-GCM；Secret 不出本机、不进日志。
- 同步互斥对象 `shurufa/.../sync.lock`：用 OSS `x-oss-forbid-overwrite` 创建；正常结束写 `released` 标记（覆盖写），异常锁超过 120 秒可被下一台覆盖回收。部分网络（如 jdmbp14）DELETE 请求会稳定超时，因此同步路径**不使用 DELETE**；测试连接也不删除探测对象。
- 同一词条两边都改时按字段合并：一方改别名、另一方改热词可同时保留；同一字段冲突取较新版本，并保留远端加密副本到 `~/Library/Application Support/Squirrel/RimeSync/backups/`。
- 删除用 tombstone 传播，不依赖“文件里缺失”。
- 单 bundle 上限 16 MB；单次同步在锁内完成；网络失败会在状态栏显示 HTTP/网络错误，下一次自动/手动重试。

本机状态：

```text
~/Library/Application Support/Squirrel/RimeSync/state.json
~/Library/Application Support/Squirrel/RimeSync/backups/<timestamp>/remote.enc
```

`state.json` 目录 0700、文件 0600；只含 device ID、同步时间、记录基线和远端 ETag，不含 Secret 或明文词条。

## 与 dotfiles/旧软链的边界

启用 OSS 后，`custom_phrase.txt` 和 `mixed_user_dictionary.json` 由同步服务管理，**不要**再把它们软链到 dotfiles，否则 OSS 和 Git 会同时写一个文件。仓库里的 `rime/custom_phrase.txt` 只是个人备份，不是部署源。

从旧机器迁移：

1. 备份 `~/Library/Rime` 和现有 symlink。
2. 把 `custom_phrase.txt` 目标内容复制为普通文件；移除 `*.custom.yaml`/Lua 的 dotfiles 软链（包内已有默认值）。
3. 用当前 `/Library/Input Methods/Squirrel.app/Contents/SharedSupport` 重新 `rime_deployer --build`。
4. `Squirrel --reload`，确认输入/`/fh`；再在设置页保存 OSS 凭证。

## 测试

```sh
bash rime/tools/test_rime_sync.sh
RIME_SYNC_AK='...' RIME_SYNC_SK='...' bash rime/tools/test_rime_sync.sh
```

离线覆盖 OSS V1 签名向量、AES-GCM、词典文件往返/注释、字段合并、删除/复活、冲突、userdb 路径、DELETE-free 锁和模拟双机同步。真实测试从环境读凭证，在唯一 `shurufa/rime-sync-live-<uuid>/` 前缀下创建加密对象并验证双向合并；不会碰生产 prefix。凭证不要写进命令历史、仓库或聊天。

桌面验收：在一台机器加入测试词/勾选热词/别名，保存后关闭词典窗口，点“立即同步”；在另一台机器点“立即同步”确认出现。两台各输入并选择一个新词，分别同步后确认对方候选可见。真实 Keychain 保存、真实个人词库和跨机 Rime userdb 合并必须在两台实际机器上验收。

## 限制与恢复

- 同一时刻只有一台持有锁；另一台等下一次触发。锁超过 120 秒才会被回收。
- Rime 学习快照的跨机合并能力由 Rime 决定；真实双机测试通过后才算保证。
- 不要在两台机器同时编辑同一词条的同一字段；冲突会保留备份但只自动选一个版本。
- 凭证/权限撤销后自动同步停止，设置页显示错误；不影响本机输入。
- 如果远端 bundle 无法解密（Secret 更换/远端损坏），不要反复覆盖；先确认 Secret，再删除/重建远端同步对象或按备份恢复。不要让另一台机器用旧 Secret 与新 bundle 混跑。
