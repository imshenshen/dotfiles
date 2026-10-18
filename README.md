# 初始化
## 准备工作
1. 安装xcode ，之后执行 `xcode-select --install`
2. 安装字体文件 https://www.nerdfonts.com/font-downloads
3. 

## 初始化
```bash
git clone git@github.com:imshenshen/dotfiles.git ~/.dotfiles
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
Make
# edit ~/.gitconfig turn proxy config
# brew bundle dump --file=Brewfile
```
## 电脑配置
1. 系统偏好设置
   2. 桌面与程序坞
      3. 调度中心：关闭重排空间
   4. 键盘
      6. 快捷键：关闭各种快捷键

## iterm2配置
1. 安装主题`${HOME}/.dotfiles/iterm2/OneHalfDark.itermcolors`和`${HOME}/.dotfiles/iterm2/OneHalfLight.itermcolors`
2. 执行`tic ${HOME}/.dotfiles/iterm2/xterm-256color.terminfo`
2. 执行`tic ${HOME}/.dotfiles/iterm2/xterm-256color-italic.terminfo`
3. iterm2 -> 设置 -> General -> preferences 设置配置文件路径为`${HOME}/.dotfiles/iterm2`
4. iterm2支持TouchID： https://apple.stackexchange.com/questions/259093/can-touch-id-for-the-mac-touch-bar-authenticate-sudo-users-and-admin-privileges
5. 安装 AI Plugin https://iterm2.com/ai-plugin.html

## fish配置
```bash
ln -s $HOME/.dotfiles/fish/* $XDG_CONFIG_HOME/fish/
```

## 安装输入法
1. 安装 https://rime.im ，https://github.com/rime/plum
2. 配置 -> 用户设定
```bash
curl -fsSL https://raw.githubusercontent.com/rime/plum/master/rime-install | bash -s -- prelude wubi pinyin-simp luna-pinyin gaboolic/rime-frost:others/recipes/full
ln -sf "$HOME"/.dotfiles/rime/*.yaml "$HOME"/.dotfiles/rime/*.txt "$HOME/Library/Rime/"
mkdir -p "$HOME/Library/Rime/lua"
ln -sf "$HOME/.dotfiles/rime/lua/wubi_pinyin_router.lua" "$HOME/Library/Rime/lua/"
```
3. 设置 -> 重新部署

五笔恢复第五码顶字上屏：前四码同时查五笔和正常拼音音节，五笔优先；前一轮没有拼音候选且首选是完整五笔词时，第五码提交首选并开始下一组编码。出现拼音候选则保留整串，`zhongguo` 不会丢掉首字母；`aaaa` 这类同时有效的编码会保守地继续拼音。显式短拼音反查入口是 `zz`。空格和选字键确认候选，分号和单引号保留原来的第二、第三候选快捷键。需安装原生插件版本 3 并同步 `wubi86_pinyin.schema.yaml`；云候选交错排序、服务开关及缓存说明见 [Rime 云候选](rime/cloud-research.md)。

本配置的云候选组件需要按 [编译和安装新版鼠须管](rime/build-squirrel.md) 安装包含原生云插件的上游构建，官方稳定版安装包没有这个自定义插件。其他电脑可直接安装本机生成的双架构安装包，默认配置已包含在包中。

已加入 [Apple 本地语音输入](rime/voice-input.md) 与[豆包二遍识别](rime/doubao-speech.md)：支持左右 Option 或自定义组合键、实时显示、手动编辑保护、跨应用继续录音与同一浮条编辑复制。共用词典可选择要随请求携带的豆包热词。当前不提供语音撤回，智能整理预留接口。Apple 本地需要 macOS 26 和兼容中文模型；豆包运行路径以 macOS 13 为部署目标，凭证保存在本机钥匙串。其他电脑不用重新编译，按[单个 PKG 安装与更新](rime/migrate-mac.md)直接安装；更新保留本地词库和个人设置。

4. 删除 Mac 默认 ABC 输入法：
5. 
    ```bash
    # 1. 删除多余的输入法，只保留默认的英文输入法和正在使用的输入法
    # 2. 
    sudo vim ~/Library/Preferences/com.apple.HIToolbox.plist # 在AppleEnabledInputSources 中删除 ABC
    # 3. 重启电脑
    ```
## Chrome
### 添加 TabToWindows 扩展
* 管理扩展程序 -> 启用开发者模式 -> 加载已解压的扩展程序 -> 选择TabToWindows文件夹
* 管理扩展程序 -> 键盘快捷键 -> TabToWindows -> 激活快捷键 -> 设置为 `⇧⌘O` 

## Raycast
1. 在 raycase/myExtensions/yabai中，执行下npm run dev，就可以在raycast中使用yabai的命令了
