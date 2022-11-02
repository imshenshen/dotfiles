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
	curl https://git.io/fisher --create-dirs -sLo ${XDG_CONFIG_HOME}/fish/functions/fisher.fish
	fisher install jethrokuan/z
	echo /usr/local/bin/fish | sudo tee -a /etc/shells
	chsh -s /usr/local/bin/fish
	$(brew --prefix)/opt/fzf/install

neovim:
	ln -sf ${DOTFILES}/neovim ${XDG_CONFIG_HOME}/nvim
	python3 -m pip install --upgrade pynvim
	git clone --depth 1 https://github.com/wbthomason/packer.nvim ~/.local/share/nvim/site/pack/packer/start/packer.nvim
	nvim +PackerInstall +qall

skhd:
	mkdir -p ${XDG_CONFIG_HOME}/skhd
	ln -sf "$(DOTFILES)/.skhdrc" "$(XDG_CONFIG_HOME)/skhd/skhdrc"
	brew services restart skhd

yabai:
	mkdir -p ${XDG_CONFIG_HOME}/yabai
	ln -s ${DOTFILES}/yabai/yabairc ${XDG_CONFIG_HOME}/yabai/yabairc
	brew services restart yabai

nodejs:
	npm install -g commitizen
	npm install -g http-server
	npm install -g conventional-changelog
	npm install -g conventional-gitlab-releaser
	npm install -g conventional-changelog-cli

.PHONY: all init git brew fish neovim skhd yabai nodejs
