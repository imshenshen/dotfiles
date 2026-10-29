# Developer ID 签名与公证

正式分发包必须同时有 Developer ID Application、Developer ID Installer 和 Apple 公证。日常安装包的电脑不需要这些文件或私钥。

## 1. 身份与配置

需要的不是 App Store 的 App ID/描述文件：

- **Developer ID Application**：签名 Squirrel.app、嵌套 framework、XPC、RimeVoice helper。
- **Developer ID Installer**：签名最终 `.pkg`。
- 私钥必须在本机登录钥匙串；公共证书本身不能代替签名能力。

本机非敏感配置在 Git 忽略的 `rime/.build/signing/release.json`：

```json
{
  "application_identity": "Developer ID Application: Your Name (TEAMID)",
  "team": "TEAMID",
  "installer_identity": "Developer ID Installer: Your Name (TEAMID)",
  "notary_profile": "squirrel-notary"
}
```

从 `security find-identity -v -p basic` 核对名称和 Team ID。不要写密码、私钥、API Key 或 Token。

首次申请 Installer 证书时，可用一次性的 `rime/native/signing/create_installer_csr.swift` 在本机生成私钥和公开 CSR；它不属于构建路径，生成后按 Apple Developer 门户流程签发并导入证书。不要把生成的私钥导出到仓库或聊天。

## 2. 公证凭证

推荐在用户自己的终端运行一次：

```sh
cd /Users/shenshen/.dotfiles
bash rime/tools/configure_notarization.sh
```

脚本使用 Apple 官方 `notarytool`，让用户输入 Apple Account 和应用专用密码；验证成功后只把 profile 名写入 `release.json`，密码只进 Keychain。也支持已有 profile：

```sh
xcrun notarytool store-credentials squirrel-notary --team-id YOUR_TEAM_ID
```

没有应用专用密码时，按 Apple 官方说明创建；不要发到聊天或提交到仓库。凭证失效/Keychain 锁定时，重新运行配置或在系统钥匙串认证后重试。

## 3. 签名/打包命令

```sh
bash rime/tools/build_squirrel.sh      # 完整构建 + 打包 + 公证
bash rime/tools/package_squirrel.sh    # 只重打包已有构建件
```

`package_squirrel.sh` 在没有完整身份时会拒绝正式发布；`SQUIRREL_ADHOC=1` 只用于开发，产物不可作为正式更新分发。签名顺序是从内到外：嵌套 framework/XPC/helper/app，再最外层 App；每个 Mach-O 使用同一 Team，启用 Hardened Runtime 和安全时间戳。录音相关 helper 仅保留所需 entitlement。

## 4. 公证判定

`package_squirrel.sh` 会自动调用：

```sh
bash rime/tools/notarize_squirrel.sh \
  /absolute/path/Squirrel-version.pkg squirrel-notary
```

只有看到以下全部结果才算完成：

- `Notarization: Accepted`
- 票据 `stapler validate` 成功
- `spctl -a -vv -t install` 返回 `accepted`，来源为 `Notarized Developer ID`

`Submitted`、`In Progress`、仅签名、仅本地 Gatekeeper 通过都不等于已公证。脚本会记录 submission ID、装订后哈希和 `dist/SHA256SUMS`；超时后复用同一哈希请求，不重复提交。Apple 拒绝时查看保存的错误日志，不要反复重传同一失败包。

## 5. 常见故障

- **钥匙串提示签名私钥**：在系统窗口允许当前终端/构建进程使用；不要导出私钥。
- **`security find-identity` 返回 0**：先在普通 GUI 终端确认，受限 SSH/沙箱环境可能读不到登录钥匙串。
- **公证凭证不可用**：运行 `configure_notarization.sh` 或解锁 Keychain 后重试；不要用环境变量把密码放进命令历史。
- **Gatekeeper 不接受**：先检查 PKG 是否被装订、是否被重新打包改变哈希，再检查签名身份和 Apple 公证状态。
- **更新后权限/Keychain 失效**：从临时签名迁移到同身份正式签名可能要求一次重新授权；不要通过重置全部 TCC 或放宽钥匙串权限掩盖问题。
