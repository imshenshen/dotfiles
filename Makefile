SHELL := /bin/bash
# https://github.com/camspiers/dotfiles/blob/master/Makefile
XDG_CONFIG_HOME=${HOME}/.config
DOTFILES=${HOME}/.dotfiles

all: init git brew fish neovim skhd yabai nodejs

init:
	mkdir -p ${XDG_CONFIG_HOME}

git:
	ln -sf ${DOTFILES}/git/.gitconfig ${HOME}/.gitconfig

brew:
	brew bundle --file="$(DOTFILES)/homebrew/Brewfile"

fish:
	mkdir -p ${XDG_CONFIG_HOME}/fish
	ln -sf ${DOTFILES}/fish/config.fish ${XDG_CONFIG_HOME}/fish/config.fish
	mkdir -p ${XDG_CONFIG_HOME}/fish/functions
	curl https://git.io/fisher --create-dirs -sLo ${XDG_CONFIG_HOME}/fish/functions/fisher.fish
	echo $(brew --prefix)/bin/fish | sudo tee -a /etc/shells
	#chsh -s $(shell brew --prefix)/bin/fish
	#fish && fisher install jethrokuan/z
	$(shell brew --prefix)/opt/fzf/install

neovim:
	if [ -d "${XDG_CONFIG_HOME}/nvim" ]; then echo "nvim config exist in ${XDG_CONFIG_HOME}/nvim" && mv ${XDG_CONFIG_HOME}/nvim ${XDG_CONFIG_HOME}/nvim.back ; fi
	git clone https://github.com/NvChad/NvChad ${XDG_CONFIG_HOME}/nvim --depth 1
	ln -sf ${DOTFILES}/neovim/custom ${XDG_CONFIG_HOME}/nvim/lua/custom
	#python3 -m pip install --upgrade pynvim
	#git clone --depth 1 https://github.com/wbthomason/packer.nvim ~/.local/share/nvim/site/pack/packer/start/packer.nvim
	#nvim +PackerInstall +qall

skhd:
	mkdir -p ${XDG_CONFIG_HOME}/skhd
	ln -sf "$(DOTFILES)/.skhdrc" "$(XDG_CONFIG_HOME)/skhd/skhdrc"
	skhd --restart-service

yabai:
	mkdir -p ${XDG_CONFIG_HOME}/yabai
	ln -sf ${DOTFILES}/yabai/yabairc ${XDG_CONFIG_HOME}/yabai/yabairc
	ln -sf ${DOTFILES}/yabai/arrangeSpace.sh ${XDG_CONFIG_HOME}/yabai/arrangeSpace.sh
	yabai --restart-service

nodejs:
	volta setup
	volta install yarn
	volta install pnpm
	volta install commitizen
	volta install http-server
	pnpm install-completion fish

.PHONY: all init git brew fish neovim skhd yabai nodejs
