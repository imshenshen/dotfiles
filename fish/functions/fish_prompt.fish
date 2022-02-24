function fish_prompt
	test $status -ne 0;
    and set -l status_colors 600 900 c00
    or set -l status_colors 666 666 aaa

  set -l cwd (prompt_pwd)

	set -l ahead    
	set -l behind   
	set -l diverged "⥄ "
	set -l dirty    \u2718
	set -l none     \u2714

  set -l normal_color     (set_color normal)
  set -l success_color    (set_color $fish_pager_color_progress ^/dev/null; or set_color cyan)
  set -l error_color      (set_color $fish_color_error ^/dev/null; or set_color red --bold)
  set -l directory_color  (set_color $fish_color_quote ^/dev/null; or set_color brown)
  set -l repository_color (set_color $fish_color_cwd ^/dev/null; or set_color green)
  #echo -n $GPG_TTY
  if [ (jobs -l | wc -l) -gt 0 ]
    echo -n (set_color $fish_color_error)\ ""
  end
  if git_is_repo
    set root_folder (command git rev-parse --show-toplevel ^/dev/null)
    set parent_root_folder (dirname $root_folder)
    set cwd (echo $PWD | sed -e "s|$parent_root_folder/||")
    echo -n -s $directory_color $cwd $normal_color
    echo -n -s $repository_color " " (git_branch_name) $normal_color " "

    if git_is_touched
      echo -n -s $error_color $dirty $normal_color
    else
      echo -n -s (git_ahead $ahead $behind $diverged $none)
    end

    if [ (git stash list | wc -l) -gt 0 ]
      echo -n (set_color $fish_color_error)" "
    end

  else
    echo -n -s $directory_color $cwd $normal_color
  end
  
	if not test -f ./package.json \
		-o -d ./node_modules \
		-o (count *.js) -gt 0
  else
    set -l node_version (node -v 2> /dev/null)
    set -l npm_version (npm --version 2> /dev/null)
    echo -ns $directory_color "  " $node_version " NPM v" $npm_version $normal_color
	end

  if not test -f go.mod \
		-o -d Godeps \
		-o -f glide.yaml \
		-o (count *.go) -gt 0 \
		-o -f Gopkg.yml \
		-o -f Gopkg.lock \
		-o ([ (count $GOPATH) -gt 0 ]; and string match $GOPATH $PWD)
  else

    set -l go_version (go version | string split ' ')

    # Go version is either the commit hash and date (devel +5efe9a8f11 Web Jan 9 07:21:16 2019 +0000)
    # at the time of the build or a release tag (go1.11.4)
    # https://github.com/matchai/spacefish/issues/137
    if test (string match 'devel*' $go_version[3])
      set go_version $go_version[3]":"(string sub -s 2 $go_version[4])
    else
      set go_version "v"(string sub -s 3 $go_version[3])
    end

    echo -ns $directory_color "  " $go_version $normal_color
	end

  echo ""
  for color in $status_colors
    echo -n (set_color $color)">"
    #echo -n (set_color $color)\uf460
  end
  echo -n " "
end

