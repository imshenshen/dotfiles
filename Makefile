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
	fisher add jethrokuan/z
	echo /usr/local/bin/fish | sudo tee -a /etc/shells
	chsh -s /usr/local/bin/fish
	$(brew --prefix)/opt/fzf/install

neovim:
	mkdir -p ${XDG_CONFIG_HOME}/nvim
	ln -sf ${DOTFILES}/neovim/init.vim ${XDG_CONFIG_HOME}/nvim/init.vim
	ln -sf ${DOTFILES}/neovim/coc-settings.json ${XDG_CONFIG_HOME}/nvim/coc-settings.json
	python3 -m pip install --upgrade pynvim
	sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
	nvim +PlugInstall +qall

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
