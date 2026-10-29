# 构建、签名、公证、打包与安装

本文是维护者 runbook。日常只安装已发布 PKG 的电脑不需要 Xcode、源码、证书或公证账号。

## 1. 前置条件

- macOS 26 或更新版本；完整 Xcode 26（只有 Command Line Tools 不够，语音使用新 SDK）。
- CMake、`xcrun`、`pkgbuild`、`productbuild`、`notarytool`。
- Developer ID Application 和 Developer ID Installer 证书及配套私钥（在本机登录钥匙串）。
- 本机签名配置 `.build/signing/release.json`（Git 忽略）和 notarytool Keychain profile。

检查：

```sh
xcode-select -p          # 应指向 Xcode.app/Contents/Developer
xcodebuild -version
cmake --version
security find-identity -v -p basic
```

首次在本机配置公证：

```sh
cd /Users/shenshen/.dotfiles
bash rime/tools/configure_notarization.sh
```

脚本让用户在终端输入 Apple Account 和应用专用密码（不要发到聊天），验证后只把 profile 名写入 `.build/signing/release.json`；密码只进 Keychain。也可以手工：

```sh
xcrun notarytool store-credentials squirrel-notary --team-id YOUR_TEAM_ID
```

## 2. 一次完整构建

```sh
cd /Users/shenshen/.dotfiles
bash rime/tools/build_squirrel.sh
```

脚本默认固定上游提交 `0cd71a6130a5866b0ae6ba0494929ebdc8211194`。它会：

1. 恢复/检查 `.build/squirrel` 工作树，重新应用 `native/squirrel/` 的五个补丁。
2. 运行上游 `action-install.sh` 获取固定依赖和 plum preset。
3. `build_voice.sh` 编译双架构 `RimeVoice.app` 和 `libRimeVoiceBridge.dylib`。
4. `build_cloud_plugin.sh` 编译双架构云候选插件，并复制默认数据。
5. `xcodebuild` 生成 `RimeVoice`/Squirrel 前端产物。
6. 写入 `LocalBuild.plist`，预编译 Rime 数据。
7. 调用 `package_squirrel.sh` 做最终签名、PKG、公证、装订和 Gatekeeper 验证。
8. 在检测到 Mac 豆包引擎时调用 `build_doubao_push.sh`；失败只警告，不影响 Squirrel 包。

产物：

```text
rime/.build/squirrel/build/Build/Products/Release/Squirrel.app
rime/.build/squirrel/package/Squirrel.pkg
rime/dist/Squirrel-<version>.pkg
```

`build_squirrel.sh` 会打印 `Release package:`；以这个路径和最终 SHA 为准，不要从 `dist/` 里挑旧包。

环境变量：

- `SQUIRREL_REF=<commit>`：明确更换上游提交；默认已固定，不建议随手用 `master`。
- `SQUIRREL_RELEASE_VERSION=<version>`：指定版本；默认 UTC 时间戳，必须递增。
- `SQUIRREL_ADHOC=1`：临时 ad-hoc 签名，只用于开发；不能作为正式更新分发。
- `SQUIRREL_SIGN_CONFIG` / `SQUIRREL_SIGN_IDENTITY` / `SQUIRREL_SIGN_TEAM` / `SQUIRREL_INSTALLER_IDENTITY` / `SQUIRREL_NOTARY_PROFILE`：覆盖本机签名配置。

## 3. 只重新打包

如果已有一个完整构建件，只改发布数据或安装器文案，可以：

```sh
bash rime/tools/package_squirrel.sh
```

它会重新 stage、重新签名、重新生成 PKG 并再次公证；不会重新下载/编译前端，也不会替本机安装。正式发布仍要求 notary profile；缺少时脚本会停止。

## 4. 发布前测试

最低门槛：

```sh
bash rime/tools/test_voice_preferences.sh
python3 rime/tests/release_defaults_test.py \
  rime/.build/squirrel/build/Build/Products/Release/Squirrel.app
```

涉及 UI、安装器、Rime 配置或发布数据时，再按 [testing](testing.md) 执行专项/人工验收。`release_defaults_test.py` 会用空 profile 部署打包数据并验证混输、默认配置和个人数据排除。

## 5. 验证 PKG

```sh
pkg=rime/dist/Squirrel-<version>.pkg
pkgutil --check-signature "$pkg"
spctl -a -vv -t install "$pkg"          # 应显示 accepted / Notarized Developer ID
xcrun stapler validate "$pkg"
shasum -a 256 "$pkg"
```

验证 App：

```sh
app=rime/.build/squirrel/build/Build/Products/Release/Squirrel.app
plutil -p "$app/Contents/Resources/LocalBuild.plist"
codesign --verify --deep --strict "$app"
lipo -archs "$app/Contents/MacOS/Squirrel"   # arm64 x86_64
```

公证提交状态必须看到 `Notarization: Accepted`，并有 `PASS: notarization accepted, ticket stapled and Gatekeeper validation passed`。`Submitted`、`In Progress` 和仅签名都不是可分发状态。

## 6. 安装

### 本机

```sh
bash rime/tools/install_squirrel.sh
```

脚本会：

- 校验构建件签名；
- 备份当前 `/Library/Input Methods/Squirrel.app` 和 `~/Library/Rime` 到 `.build/backups/<timestamp>.XXXX/`；
- 等待鼠须管进程退出；
- 通过 macOS 管理员认证安装 PKG；
- 逐字节比较主程序、语音桥、录音助手和云插件。

它不会修改用户词库内容，不会强制注销，不会自动切换输入源。

### 另一台 Mac

复制 `rime/dist/Squirrel-<version>.pkg`，双击安装。安装器只替换 App，保留 `~/Library/Rime`、偏好和 Keychain。首次安装可能需要在系统设置中添加鼠须管；升级通常不需要重新添加。若菜单异常，先保留现场并核对 `LocalBuild.plist`，不要反复重装或删输入源。

首次使用语音需要各自授予麦克风和辅助功能（辅助功能已授权时不要求输入监控），并在本机保存自己的豆包/OSS 凭证。

## 7. 回滚

安装脚本保留：

```text
rime/.build/backups/original.txt
rime/.build/backups/latest.txt
```

读取备份目录，退出鼠须管，将当前 App 另存后再恢复：

```sh
backup_dir="$(cat rime/.build/backups/original.txt)"
"/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --quit
sudo mv "/Library/Input Methods/Squirrel.app" "$backup_dir/Squirrel.after-upgrade.app"
sudo ditto "$backup_dir/Squirrel.app" "/Library/Input Methods/Squirrel.app"
```

应用回滚不会自动回滚用户词库；如需恢复 `~/Library/Rime`，先备份当前目录，再复制备份中的 `Rime`。恢复词库会丢失备份时间之后的输入学习记录。方案/云插件版本不匹配时，优先以备份中的 `Rime/build` 作为部署参考，不要直接覆盖用户词典。

## 8. 发布纪律

- 不把 `.build/`、`dist/`、`release.json`、个人词条、userdb、Keychain、日志或签名私钥提交到 Git。
- 每次正式发布记录：版本、PKG SHA-256、公证 submission ID、是否 Accepted/装订/Gatekeeper、测试和人工验收范围。
- 不把“编译成功”“公证通过”“包内文件一致”当作输入法在桌面真的可用的证据；安装后的 IMK 菜单、实际输入、语音/GIF/OSS 仍需人工验收。
- 安装器文案、默认数据和 `LocalBuild.plist` 的改动会影响包内文件；如果只改本文档，不需要重新构建或公证。
