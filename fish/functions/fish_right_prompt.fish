#function fish_right_prompt
  #if git_is_repo
    #set -l npm_version ( npm run env ^/dev/null | grep npm_package_version | cut -d = -f 2)
    #echo -n -s (set_color $fish_color_cwd)\uf898 "$npm_version"
  #end
#end

#function npm_is_repo
  #test -e package.json
#end
function fish_right_prompt
  if test (echo $http_proxy | wc -w) -eq 1
    set_color green
    echo 
  end
end
