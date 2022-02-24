#set -Ux LANG en_US
#set -x GOPATH $HOME/go
#set PATH $PATH $GOPATH/bin /Users/caowenlong/Documents/flutter/bin /usr/local/opt/python@3.8/bin
set -x XDG_CONFIG_HOME $HOME/.config
set -x RIPGREP_CONFIG_PATH $XDG_CONFIG_HOME/.ripgreprc
set -x EDITOR "nvim"
set -x TERM "xterm-256color-italic"
set -x SASS_BINARY_SITE https://npm.taobao.org/mirrors/node-sass/

source ~/.config/fish/secret.fish
# i use xterm-256color-italic ,but remote server may not have it, reset it!
alias ssh='env TERM="xterm-256color" ssh'
alias goproxy='export http_proxy=http://127.0.0.1:1087 https_proxy=http://127.0.0.1:1087'
alias disproxy='set -e http_proxy ; set -e https_proxy'
alias gitproxy='git config --global http.https://github.com.proxy socks5://127.0.0.1:1086'
alias disgitproxy='git config --global --unset http.https://github.com.proxy'
alias vim=nvim
alias jnpm="npm --registry=http://registry.m.jd.com"
alias tcc="tmux -CC"
alias python2="/usr/bin/python"
alias python3="/usr/local/bin/python3"
alias python=python3
#alias weather="curl wttr.in/"

#if test -n $ITERM_PROFILE
  #switch $ITERM_PROFILE
    #case "Light"
      #echo "Light"
      #set -l fish_color_comment 5c6773
      #set -l fish_color_command f29e74
      #set -l fish_color_normal 3e4b59
      #set -l fish_color_quote b8cc51
      #set -l fish_color_error ff3333
      #set -l fish_color_cwd 73d0ff
      #set -l fish_color_autosuggestion 5c6773
      #set -l fish_color_param 95e6cb
      #set -l fish_pager_color_completion d4bfff
  #end
#end

set -x GPG_TTY (tty)

set -U Z_CMD "j"

thefuck --alias | source

test -e {$HOME}/.iterm2_shell_integration.fish ; and source {$HOME}/.iterm2_shell_integration.fish

#cat ~/.cache/wal/sequences &
#set -g fish_user_paths "/usr/local/opt/sphinx-doc/bin" $fish_user_paths
set -g fish_user_paths "/usr/local/opt/python@3.8/bin" $fish_user_paths

