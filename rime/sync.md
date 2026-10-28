# 词库自动同步（阿里云 OSS）

> 状态：2026-10-28。同步固定词条、语音别名、热词和 Rime 学习词库快照；凭证只在钥匙串。

## 数据范围

同步到 OSS 的一个加密 bundle：

- `custom_phrase.txt`：固定短语、编码和权重
- `mixed_user_dictionary.json`：语音识别别名、豆包热词勾选、导入来源和排除墓碑
- Rime `sync/*/*.userdb.txt`：学习词库快照

不会上传 `*.userdb` 原始 LevelDB、`installation.yaml`、`user.yaml`、听写历史、语音快捷键或任何 Key。

学习词库不是直接复制运行中的 userdb，而是：

1. 下载其他电脑的 `*.userdb.txt` 快照到本机 `~/Library/Rime/sync/`
2. 调用 Rime 的 `sync_user_data()` 合并
3. 再收集本机快照上传

每个 installation id 保留自己的快照，Rime 负责合并；不会在 Rime 写入时直接搬运 LevelDB 文件。

## 配置

输入法菜单 → **词库自动同步…**：

- OSS endpoint：默认 `https://ss-storage-private.oss-cn-beijing.aliyuncs.com`
- bucket：`ss-storage-private`
- prefix：必须是 `shurufa/` 下的路径，默认 `shurufa/rime-sync/v1`
- AccessKey ID / Secret：只保存到 macOS 钥匙串，不写入 YAML、dotfiles、日志或安装包
- “测试连接”会在 prefix 下创建并删除一个随机探测对象
- “立即同步”立即执行；自动同步在词典保存后、启动约 20 秒后以及每 10 分钟触发

首次在一台电脑配置后，另一台电脑填入相同凭证即可。两台电脑应使用同一个 OSS bucket/prefix 和同一个 AccessKey Secret。

## 加密与并发

- Bundle 用 AES-GCM 加密；密钥由 AccessKey Secret 通过 HKDF-SHA256 在本机派生。Secret 不出本机，也不进入日志。
- **更换 AccessKey Secret 后，远端旧 bundle 无法解密**；需要先删除远端对象或重新初始化同步。不要把 Secret 写进 dotfiles。
- OSS 请求使用 ephemeral URLSession、HTTPS、超时和最多 16 MB bundle 上限。
- 同步期间通过 `shurufa/.../sync.lock` 互斥；锁由 OSS `x-oss-forbid-overwrite` 创建。异常退出留下的锁超过 120 秒后才会被下一台电脑回收。
- 同一词条两边都修改时按字段合并：一方改了别名、另一方改了热词会同时保留；同一字段冲突取较新版本，并保留远端加密副本到本机 `RimeSync/backups/`。
- 删除用 tombstone 传播，不依赖“文件里缺失”判断。

## 与 dotfiles 的边界

启用 OSS 同步后，`custom_phrase.txt` 和 `mixed_user_dictionary.json` 应该由同步服务管理，**不要再把 `custom_phrase.txt` 软链到 dotfiles**。否则 OSS 和 Git 会同时写一个文件，容易产生冲突。dotfiles 只保留代码、默认 YAML/Lua 和测试；个人词库属于 OSS 数据。

配置文件和 Lua 继续按包内默认/部署流程处理，不需要软链。

## 测试

离线：

```sh
bash rime/tools/test_rime_sync.sh
```

覆盖 OSS V1 签名向量、AES-GCM、词典文件往返与注释、字段合并、删除/复活、冲突、userdb 路径校验、加密 bundle 和模拟双机同步。

真实 OSS（凭证只从环境读取，不写入仓库）：

```sh
RIME_SYNC_AK='...' RIME_SYNC_SK='...' bash rime/tools/test_rime_sync.sh
```

真实测试会在 `shurufa/rime-sync-live-<uuid>/` 下创建加密对象，验证两台临时机器双向合并，然后删除对象。

桌面验收：在一台电脑的用户词典加入一条测试词并勾选热词/别名，保存后关闭窗口，等待同步完成；在另一台电脑打开“词库自动同步…”立即同步，确认词条和别名出现。再测试 Rime 学习词：两台电脑各输入并选择一个新词，分别同步后确认两边都能在候选中看到对方的词。

## 限制

- 同步不是实时协同；同一时刻只有一台电脑能持有锁，另一台会等待下一次触发。
- Rime 学习快照的合并能力由 Rime 自身决定；真实双机测试通过后才应把它当作跨机学习词库的保证。
- 不要在两台电脑同时编辑同一条词的同一字段；冲突会保留备份，但只自动选择一个版本。
- 如果 OSS bucket 或 RAM 权限撤销，自动同步会停止并在设置页显示错误；不会影响本机输入。
