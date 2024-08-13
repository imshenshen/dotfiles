SHELL := /bin/bash
# https://github.com/camspiers/dotfiles/blob/master/Makefile
XDG_CONFIG_HOME=${HOME}/.config
DOTFILES=${HOME}/.dotfiles

all: init git brew neovim skhd nodejs yabai fish aerospace

init:
	mkdir -p ${XDG_CONFIG_HOME}

git:
	ln -sf ${DOTFILES}/git/.gitconfig ${HOME}/.gitconfig

brew:
	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	brew bundle --file="$(DOTFILES)/homebrew/Brewfile"

fish:
	mkdir -p ${XDG_CONFIG_HOME}/fish
	ln -sf ${DOTFILES}/fish/config.fish ${XDG_CONFIG_HOME}/fish/config.fish
	echo $(brew --prefix)/bin/fish | sudo tee -a /etc/shells
	chsh -s $(brew --prefix)/bin/fish
	# after this ,use fish to install fisher
	curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher
	fisher install jethrokuan/z
	fisher install g-plane/pnpm-shell-completion
	$(shell brew --prefix)/opt/fzf/install

neovim:
	if [ -d "${XDG_CONFIG_HOME}/nvim" ]; then echo "nvim config exist in ${XDG_CONFIG_HOME}/nvim" && mv ${XDG_CONFIG_HOME}/nvim ${XDG_CONFIG_HOME}/nvim.back ; fi
	ln -sf ${DOTFILES}/neovim ${XDG_CONFIG_HOME}/nvim
	#python3 -m pip install --upgrade pynvim
	#:MasonInstallAll

skhd:
	mkdir -p ${XDG_CONFIG_HOME}/skhd
	ln -sf "$(DOTFILES)/.skhdrc" "$(XDG_CONFIG_HOME)/skhd/skhdrc"
	skhd --restart-service

yabai:
	#https://github.com/koekeishiya/yabai/wiki/Installing-yabai-(latest-release)
	ln -sf ${DOTFILES}/yabai ${XDG_CONFIG_HOME}/yabai
	(cd ${DOTFILES}/yabai/yabai-helper-server && npm i)
	pm2 start ${XDG_CONFIG_HOME}/yabai/yabai-helper-server/server.js --name yabai-helper-server
	echo "$(whoami) ALL=(root) NOPASSWD: sha256:$(shasum -a 256 $(which yabai) | cut -d " " -f 1) $(which yabai) --load-sa" | sudo tee /private/etc/sudoers.d/yabai
	yabai --start-service
	sudo yabai --load-sa

aerospace:
	ln -sf ${DOTFILES}/aerospace ${XDG_CONFIG_HOME}/aerospace
	mkdir -p ${XDG_CONFIG_HOME}/borders
	ln -sf ${DOTFILES}/bordersrc ${XDG_CONFIG_HOME}/borders/bordersrc

nodejs:
	volta setup
	volta install node@latest
	volta install yarn
	volta install pnpm
	volta install commitizen
	volta install http-server
	pnpm install-completion fish
	npm install -g pm2@latest

.PHONY: all init git brew fish neovim skhd yabai nodejs aerospace
