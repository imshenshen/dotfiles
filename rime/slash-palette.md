# 符号与 GIF 大面板（`/fh` / `/gif`）

> 状态：2026-10-28。原生面板、GIF 搜索和 Rime 直接 ASCII 已接入；最终安装包需按本文验收后再分发。

中文模式下，`` ` ``、`#`、`%`、`*` 直接输入 ASCII 字符，不再弹出候选列表。输入 `/fh` 打开可搜索的分类符号面板；输入 `/gif` 打开同一个大的在线 GIF 搜索面板。普通 `/`、`/bq`、`/mac` 以及其他 Rime `/xx` 类别保持原行为。

## 直接 ASCII

`rime/wubi86.custom.yaml`、`rime/rime_frost.custom.yaml` 和 `rime/luna_pinyin_simp.custom.yaml` 都保留了半角/全角的标量标点补丁，同时注册了 `lua_processor@*slash_literal`（`rime/lua/slash_literal.lua`）。Lua 处理器在空组合、中文模式下直接提交四个字符：

- 半角/全角模式都提交 ASCII，不显示候选。
- 全角模式由 librime 的全局 `shape_formatter` 处理；处理器在提交瞬间临时关闭 `full_shape`，提交后立即恢复，避免变成 `＃`、`％`、`＊`、`｀`。
- 正在组合时（例如五笔的 `*` 通配符）不拦截，仍交给正常输入流程。
- 英文模式不拦截，交给宿主和原有直通输入。
- 处理器放在 `ascii_composer` 之后、`speller` 之前；`ascii_composer` 仍能看到 Shift+3，因此松开 Shift 不会误切中英文。
- `rime_frost` 的 `` ` `` 辅助码触发与直接 ASCII 冲突；按用户要求，空组合下 `` ` `` 直接上屏，辅助码需改用其他方式。
- `luna_pinyin_simp` 的 `` ` `` 原本用于笔画反查；为满足直接上屏，`recognizer/patterns/reverse_lookup` 被设为 `^$` 停用该反查。这是唯一明确的行为取舍。
- 中文模式无法再直接输入字面量 `/gif` 文本；需要时切换到英文模式。

## `/fh` 面板

输入 `/fh` 后，Squirrel 在 Rime 处理完按键后读取精确的原始输入，清除这次组合的标记文字，然后显示非激活面板；`/fh` 本身不会留在宿主输入框。面板使用现有的 158 个非 ASCII `/fh` 符号，并内置中文名、英文 Unicode 名、全拼、拼音首字母和 Unicode 十六进制搜索。

- 左侧是分类：商标与版权、警示与标志、自然与地点、体育与娱乐、方向与手势、工具与科学、其他。
- 顶部只读查询行由输入控制器驱动，不创建第二个 Rime 组合，也不会把焦点移到面板。
- `↑↓←→` 移动，`PageUp/PageDown` 翻页，`Tab/Shift-Tab` 切换分类，`Return` 插入，`Esc` 先清查询再关闭；`Backspace` 在空查询时关闭。
- 鼠标第一次点击即可选中；符号点击直接插入。插入走现有 `commit(string:)`，保留中英文空格和宿主范围校验。
- 面板打开时 `flagsChanged` 被面板接收，避免单按 Shift 切换中英文；带 Command/Control/Option 的组合键仍交给宿主。
- 面板不调用 `NSApp.activate`、`makeKeyAndOrderFront` 或让查询行成为第一响应者；`canBecomeKey`/`canBecomeMain` 均为 `false`。切换输入源、失焦、切换前台应用、切到英文模式或开始语音时关闭。

## `/gif` 面板

`/gif` 使用与 `/fh` 相同的 900×640 非激活面板。输入英文关键词后 300 ms 防抖搜索；结果以静态首帧缩略图展示，`PageDown` 在末尾继续加载下一页，按 id 去重追加。

- 选中结果后下载完整 GIF（上限 20 MB），写入 `~/Library/Caches/im.rime.inputmethod.Squirrel/GIFSearch/<sha256>.gif`（目录 `0700`、文件 `0600`、原子替换）。
- 剪贴板同时写入 `fileURL`、`com.compuserve.gif`、首帧 TIFF/PNG 和来源 URL；成功后提示“已复制 GIF；回到输入框按 ⌘V 粘贴”，短暂关闭面板。
- **不自动粘贴**，也不通过 IMK/AX 向宿主插入图片或文字。
- 请求使用 ephemeral URLSession、无 Cookie/凭证缓存、8/20 秒超时、不跟随重定向；JSON 上限 2 MB、缩略图 5 MB。媒体和 endpoint 必须 HTTPS，拒绝 loopback、私有地址、带用户名密码的 URL 和 `.local`；Giphy/Tenor 的媒体 host 还限制为各自域名，自定义 provider 接受任意安全 HTTPS host。
- 安全输入模式（安全键盘/密码框）下不发起 GIF 搜索；已经显示的结果不会被主动刷新。
- 搜索词会发送到所选 GIF 服务；API Key 只保存在键串 `im.rime.inputmethod.Squirrel.GIFSearch` / `apiKey`，不写入 Rime 配置、日志或安装包。程序不记录查询词、Key、endpoint 或响应正文。
- 缓存启动时清理 7 天前或超过 100 MB 的文件。

### 配置

输入法菜单 → **GIF 搜索设置…**（也可在面板右下角点击）。支持：

| Provider | 地址 | Key |
| --- | --- | --- |
| Giphy | `https://api.giphy.com/v1/gifs/search`，可填代理 | 必填 |
| Tenor | `https://tenor.googleapis.com/v2/search`，可填代理 | 必填 |
| 自定义 / 代理 | 必须填写完整 HTTPS 搜索 URL | 可选，`Authorization: Bearer` |

自定义响应契约：

```json
{
  "items": [
    {
      "id": "unique-id",
      "title": "optional",
      "thumbnail_url": "https://…/thumb.gif",
      "gif_url": "https://…/full.gif",
      "width": 480,
      "height": 270,
      "source_url": "https://…/page"
    }
  ],
  "next_offset": 24,
  "has_more": true
}
```

请求为 `GET {endpoint}?q=…&limit=24&offset=…`。设置页的“测试连接”固定搜索 `hello`，只显示“连接成功 / 返回条数”或错误描述，不显示 Key 或响应正文。Giphy/Tenor 在中国大陆可能不可达；自定义 endpoint 是主路径。内容分级默认“适中”。

## Rime 配置与部署

源码文件：

- `rime/lua/slash_literal.lua`
- `rime/wubi86.custom.yaml`、`rime/rime_frost.custom.yaml`、`rime/luna_pinyin_simp.custom.yaml`
- `rime/tools/generate_symbol_catalog.py` → `rime/native/voice/SlashSymbolData.swift`

本机源码部署：

```sh
ln -sf "$HOME/.dotfiles/rime/lua/slash_literal.lua" "$HOME/Library/Rime/lua/slash_literal.lua"
"/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --reload
```

安装包的 `prepare_release_data.sh` 会复制 `luna_pinyin_simp.custom.yaml` 和 `lua/slash_literal.lua`。`rime_frost.custom.yaml` 使用 `"punctuator/symbols/+"` 合并，保留 `/bq`、`/mac` 和预设类别。

## 验证

```sh
bash rime/tools/test_slash_palette.sh
bash rime/tools/test_voice_preferences.sh
python3 rime/tests/verify_slash.py "/Library/Input Methods/Squirrel.app"
python3 rime/tests/release_defaults_test.py rime/.build/squirrel/build/Build/Products/Release/Squirrel.app
```

`test_slash_palette.sh` 验证触发状态机、158 条目录检索、Giphy/Tenor/custom 请求与解析、错误不泄露 Key、GIF 校验/缓存权限/剪贴板类型、面板非激活样式和位置钳制。`verify_slash.py` 通过隔离的 librime 用户目录验证三个方案在配置中的直接 ASCII、`/fh` 原始触发、`/bq`/`/mac`、`/gif` 和 luna 取舍；它使用仓库 `rime/distribution/data` 覆盖已安装应用的数据，避免使用旧包的方案。

`rime_frost` 的无头符号候选在当前上游数据的 Lua 辅助文件缺失时为空，但 `/fh` 的原始输入保持完整，原生面板仍会打开；因此脚本对 `rime_frost` 检查原始触发，对 `wubi86`/`luna_pinyin_simp` 检查完整的 158 项预设。普通桌面验收仍需在文本编辑、Finder 重命名、Safari、iTerm2、微信/QQ 中分别确认焦点、插入和 ⌘V 粘贴。
