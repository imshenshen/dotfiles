if test -d /opt/homebrew/
  set -gx HOMEBREW_PREFIX "/opt/homebrew";
  set -gx HOMEBREW_CELLAR "/opt/homebrew/Cellar";
  set -gx HOMEBREW_REPOSITORY "/opt/homebrew";
  set -q PATH; or set PATH ''; set -gx PATH "/opt/homebrew/bin" "/opt/homebrew/sbin" $PATH;
  set -q MANPATH; or set MANPATH ''; set -gx MANPATH "/opt/homebrew/share/man" $MANPATH;
  set -q INFOPATH; or set INFOPATH ''; set -gx INFOPATH "/opt/homebrew/share/info" $INFOPATH;
end

set -gx PATH "$HOME/bin" $PATH;
set -x XDG_CONFIG_HOME $HOME/.config
set -x RIPGREP_CONFIG_PATH $XDG_CONFIG_HOME/.ripgreprc
set -x EDITOR "nvim"
set -x TERM "xterm-256color-italic"
set -x SASS_BINARY_SITE https://npm.taobao.org/mirrors/node-sass/
# set -x VOLTA_FEATURE_PNPM 0

#set -gx http_proxy http://127.0.0.1:6152
#set -gx https_proxy http://127.0.0.1:6152
#set -gx all_proxy socks5://127.0.0.1:6153

status --is-interactive; and pyenv init - --no-rehash | source

#source ~/.config/fish/secret.fish
# i use xterm-256color-italic ,but remote server may not have it, reset it!
alias ssh='env TERM="xterm-256color" ssh'
alias goproxy='export https_proxy=http://127.0.0.1:6152;export http_proxy=http://127.0.0.1:6152;export all_proxy=socks5://127.0.0.1:6153'
alias disproxy='set -e http_proxy ; set -e https_proxy ; set -e all_proxy'
alias gitproxy='git config --global http.https://github.com.proxy socks5://127.0.0.1:1086'
alias disgitproxy='git config --global --unset http.https://github.com.proxy'
alias vim=nvim
alias jnpm="npm --registry=http://registry.m.jd.com"
alias tcc="tmux -CC"
# alias python2="/usr/bin/python"
# alias python3="/usr/bin/python3"
# alias python=python3
alias ai='gh copilot suggest -t shell'
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
#set -g fish_user_paths "/usr/local/opt/python@3.8/bin" $fish_user_paths

set -gx VOLTA_HOME "$HOME/.volta"
set -gx PATH "$VOLTA_HOME/bin" $PATH

# tabtab source for packages
# uninstall by removing these lines
[ -f ~/.config/tabtab/fish/__tabtab.fish ]; and . ~/.config/tabtab/fish/__tabtab.fish; or true

set -gx PATH "$HOME/.cargo/bin" $PATH

function starship_transient_rprompt_func
  starship module time
end
starship init fish | source
enable_transience


# bun
set --export BUN_INSTALL "$HOME/.bun"
set --export PATH $BUN_INSTALL/bin $PATH

function __filter_short_history_debug --on-event fish_prompt
    set -l last (history --max 1)
    if test -z "$last"
        return
    end
    set -l trimmed (string trim -- "$last")
    set -l len (string length -- "$trimmed")[1]
    if test $len -lt 3
        history delete --exact --case-sensitive "$trimmed" 2>/dev/null
    end
end

# fish completion for: git wta / git wtr
# Usage:
#   git wta ori<Tab>  -> origin/... remote branches
#   git wtr ori<Tab>  -> origin/... remote branches

# function __git_wt_is_subcmd --argument-names subcmd
#     # tokens without the command itself
#     set -l words (commandline -opc)
#     # words[1] is "git", words[2] is subcommand
#     test (count $words) -ge 2; and test "$words[2]" = "$subcmd"
# end
#
# function __git_wt_remote_branches
#     # Output like: origin/feat/xxx
#     command git for-each-ref --format='%(refname:strip=2)' refs/remotes 2>/dev/null \
#         | string match -r '^origin/' \
#         | sort -u
# end
#
# function __git_wt_local_branches
#     command git for-each-ref --format='%(refname:strip=2)' refs/heads 2>/dev/null \
#         | sort -u
# end
#
# # wta: prefer remote branches, also allow local
# complete -c git -n '__git_wt_is_subcmd wta' -a '(__git_wt_remote_branches)' -d 'Remote branch (origin/...)'
# complete -c git -n '__git_wt_is_subcmd wta' -a '(__git_wt_local_branches)'  -d 'Local branch'
#
# # wtr: same
# complete -c git -n '__git_wt_is_subcmd wtr' -a '(__git_wt_remote_branches)' -d 'Remote branch (origin/...)'
# complete -c git -n '__git_wt_is_subcmd wtr' -a '(__git_wt_local_branches)'  -d 'Local branch'
