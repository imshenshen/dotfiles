# git wta / wtr completions for fish (does not touch builtin git completions)

function __git_wt_is_subcmd --argument-names subcmd
    set -l words (commandline -opc)
    test (count $words) -ge 2; and test "$words[2]" = "$subcmd"
end

function __git_wt_origin_remote_branches
    # origin/<branch> from refs/remotes/origin/*, excluding origin/HEAD
    command git for-each-ref --format='origin/%(refname:strip=3)' refs/remotes/origin 2>/dev/null \
        | string match -v -r '^origin/HEAD$' \
        | sort -u
end

function __git_wt_local_branches
    command git for-each-ref --format='%(refname:strip=2)' refs/heads 2>/dev/null \
        | sort -u
end

# Add completions for git wta / wtr only (no deletion/override)
complete -c git -n '__git_wt_is_subcmd wta' -f -a '(__git_wt_origin_remote_branches)' -d 'Remote branch (origin/...)'
complete -c git -n '__git_wt_is_subcmd wta' -f -a '(__git_wt_local_branches)'          -d 'Local branch'

complete -c git -n '__git_wt_is_subcmd wtr' -f -a '(__git_wt_origin_remote_branches)' -d 'Remote branch (origin/...)'
complete -c git -n '__git_wt_is_subcmd wtr' -f -a '(__git_wt_local_branches)'          -d 'Local branch'
