# Developer ID 签名与公证

需要的不是 Identifiers 中的 App ID，而是证书页中的 Developer ID Application（应用）与 Developer ID Installer（PKG）。当前不使用 App Store、推送、iCloud 等需要额外 App ID／描述文件的服务。

2026-10-15 已确认本机有可用的 Developer ID Application，并为 Installer 生成了本机钥匙串私钥。申请文件只包含公钥及通用名称；用户在 Apple 门户签发并下载证书后，验证 Apple 证书链和申请公钥一致，导入了 Installer 证书。私钥没有导出或进入仓库。

以前在受限环境中 `security find-identity` 返回 0 个身份，是查询环境的限制；不能据此判断实际系统钥匙串没有证书。正式签名和签名验证应在普通本机终端或允许访问系统钥匙串／信任服务的执行环境中进行，受限环境也可能把有效签名报告为 invalid signature。

## 发布构建

本机的非敏感签名配置在被 Git 忽略的 `rime/.build/signing/release.json`，格式如下。证书名称和 Team ID 从 `security find-identity -v -p basic` 核对；不要写密码或私钥：

```json
{
  "application_identity": "Developer ID Application: Your Name (TEAMID)",
  "team": "TEAMID",
  "installer_identity": "Developer ID Installer: Your Name (TEAMID)",
  "notary_profile": "squirrel-notary"
}
```

正式发布要求 `notary_profile` 非空；未配置时打包会停止并提示先运行配置脚本。配置公证凭证后填入钥匙串 profile 名即可。仅本机开发可显式使用 `SQUIRREL_ADHOC=1`，开发包不能作为正式包分发。

```sh
bash rime/tools/build_squirrel.sh
# 仅重新打包已编译产物：
bash rime/tools/package_squirrel.sh
```

正式签名流程按内部文件、嵌套 App／XPC／Framework、最外层 App 的顺序签名，所有 Mach-O 使用相同 Team，开启 Hardened Runtime 和安全时间戳。主程序和录音助手仅增加需要的 audio-input 权限；去掉调试 get-task-allow 与 disable-library-validation。打包前不再对正式签名资源进行修改，Installer 使用单独的 Installer 证书签名。

开发时明确选择临时签名：`SQUIRREL_ADHOC=1 bash rime/tools/package_squirrel.sh`。不要将临时签名包当作正式更新分发。新电脑构建需在本机导入拥有配套私钥的签名身份，不能仅下载公共证书就取得签名能力；日常使用电脑只需安装发布 PKG，不需要私钥或 Xcode。

## 公证凭证：由用户在终端输入

推荐在自己的本机终端运行一次配置脚本：

```sh
cd /Users/shenshen/.dotfiles
bash rime/tools/configure_notarization.sh
```

脚本使用已有 Team ID 调用 Apple 官方 notarytool，让用户交互输入认证；验证成功后只把 profile 名写入忽略的本机配置，密码只进入钥匙串。配置失败不会启用公证配置。已有其他名称的 Keychain profile 可填入 release.json 的 notary_profile，无需重复保存密码。

也可手工调用 Apple 官方 notarytool：

```sh
xcrun notarytool store-credentials squirrel-notary --team-id YOUR_TEAM_ID
```

按提示选择 Apple Account／应用专用密码认证，输入开发者账号邮箱和应用专用密码。密码不加在命令参数中，不发到聊天中。若没有应用专用密码，请自行在 Apple Account 的登录与安全性页面生成；该凭证的创建和输入由用户完成。也可使用用户已经配置好的 App Store Connect API key profile，工具只引用 profile 名，不读取或导出其私钥。

凭证验证并保存后，配置 `release.json` 的 notary_profile。只有在用户明确允许向 Apple 上传当前 PKG 后才提交公证（包内排除了个人词库、机器身份和接口凭证）。

```sh
bash rime/tools/notarize_squirrel.sh /absolute/path/Squirrel-version.pkg squirrel-notary
```

脚本记录 submission ID 和文件哈希；Apple 接受后装订票据，验证票据并执行 Gatekeeper 验证。`Submitted`／`In Progress` 不算完成。若达到等待上限会以 75 退出并保留请求信息，下次执行会复用同一个、文件哈希匹配的请求，不重复提交。拒绝时保存 Apple 错误日志。

## 更新与授权

正式版本持续使用同一个 Team ID、Bundle ID 和兼容的指定要求（DR）。版本变化不再以单次构建 cdhash 作为应用身份。由临时签名第一次迁移至正式签名时，旧权限与钥匙串记录可能需要一次重新允许／保存，之后同身份更新通常可以继承。不要通过重置全部 TCC 记录、扩大钥匙串访问列表或降低系统安全设置来掩盖签名问题。

源码默认配置在应用内，安装器仍不会覆盖用户词库、学习记录、热词选择及已有偏好。已安装的本机旧版不会在生成签名包时被替换；安装正式包是另一步操作。

参考：[Apple Developer ID 证书](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)、[签名要求与稳定身份](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements/)、[Apple 公证](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

当前决定：2026-10-16 用户明确要求正式分发包含公证，替代此前暂缓公证的决定。首次需完成上述钥匙串认证配置；之后 build_squirrel.sh 会经 package_squirrel.sh 自动提交、等待、装订及验证，无需再次逐包确认。尚未通过 Apple 验收的旧包不能标记为已公证。

公证票据会改变 PKG 文件哈希。脚本记录提交前及装订后的哈希，重试时复用同一提交，且更新已存在的 SHA256SUMS 对应条目。上传失败不会留下半截提交状态文件。离线回归：`python3 rime/tests/notarization_workflow_test.py`。


## 首次实际公证验收（2026-10-16）

`Squirrel-20261016.041022.pkg` 已完成真实 Apple 公证，提交 ID 为 `b712910c-1afb-47c2-b12e-e54c0148420a`，Apple 状态 `Accepted`。票据装订与 `stapler validate` 通过，`spctl --assess --type install` 返回 `accepted`、`source=Notarized Developer ID`。`dist/SHA256SUMS` 已更新为装订后的哈希，兼容安装路径 `.build/squirrel/package/Squirrel.pkg` 也已同步为同一份已公证包。

本机钥匙串认证 profile 已配置，完整构建会自动执行签名、公证与验证。公证不等于安装，本次没有替换本机输入法，也没有修改系统权限或个人词典。
