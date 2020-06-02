# https://github.com/camspiers/dotfiles/blob/master/Makefile
XDG_CONFIG_HOME=${HOME}/.config
DOTFILES=${HOME}/.dotfiles

all: init brew fish neovim skhd yabai

init:
	mkdir -p ${XDG_CONFIG_HOME}

brew:
	brew bundle --file="$(DOTFILES)/homebrew/Brewfile"

fish:
	mkdir -p ${XDG_CONFIG_HOME}/fish
	curl https://git.io/fisher --create-dirs -sLo ${XDG_CONFIG_HOME}/fish/functions/fisher.fish
	fisher add jethrokuan/z

neovim:
	mkdir -p ${XDG_CONFIG_HOME}/nvim
	ln -s ${DOTFILES}/neovim/init.vim ${XDG_CONFIG_HOME}/nvim/init.vim
	ln -s ${DOTFILES}/neovim/coc-settings.json ${XDG_CONFIG_HOME}/nvim/coc-settings.json
	python3 -m pip install --upgrade pynvim
	nvim +PlugInstall +qall

skhd:
	mkdir -p ${XDG_CONFIG_HOME}/skhd
	ln -sfn "$(DOTFILES)/.skhdrc" "$(XDG_CONFIG_HOME)/skhd/.skhdrc"

yabai:
	mkdir -p ${XDG_CONFIG_HOME}/yabai
	ln -s ${DOTFILES}/yabai/yabairc ${XDG_CONFIG_HOME}/yabai/yabairc

.PHONY: all init brew fish neovim skhd yabai
