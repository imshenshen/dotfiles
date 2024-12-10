#!/bin/bash


LOCKFILE="/tmp/bindSpace.lock"
trap 'rm -f "${LOCKFILE}"; exit' EXIT

if [ -e ${LOCKFILE} ]; then
    exit 0
fi

touch ${LOCKFILE}
# 从 $HOME/.config/yabai/bindSpace.conf 中读取 binded_space 变量
source $HOME/.config/yabai/bindSpace.conf

if [[ -z $binded_space ]]; then
  exit 1
fi


#binded_space="3,7;4,8,9;6,7"
# 为避免出现Bug导致频繁调用yabai -m space --focus，请添加一个maxFocusChangeCount来限制最大执行次数
maxFocusChangeCount=10
focusChangeCount=0

all_space_info=$(yabai -m query --spaces)
current_focused_space_info=$(echo $all_space_info | jq '.[] | select(."has-focus" == true)')
current_focused_space_index=$(echo $current_focused_space_info | jq '.index')

#current_focused_space=$(yabai -m query --spaces | jq '.[] | select(."has-focus" == true).index')
echo "焦点变更为第 $current_focused_space_index 个空间。"
# 把 binded_space 按分号";"变为数组， 遍历这个数组，再根据逗号","变为数组，遍历这个数组，判断 current_focused_space 是否在数组中，如果在，则依次聚焦数组中的其他值，最后重新聚焦current_focused_space
for i in $(echo $binded_space | tr ";" "\n"); do
  for j in $(echo $i | tr "," "\n"); do
    if [[ $j -eq $current_focused_space_index ]]; then
      for k in $(echo $i | tr "," "\n"); do
        if [[ $k -ne $current_focused_space_index ]]; then
          if [[ $focusChangeCount -lt $maxFocusChangeCount ]]; then
            # 如果 $k的space和$current_focused_space_index在同一个显示器，不用聚焦
            tmp_bind_space_display=$(echo $all_space_info | jq ".[] | select(."index" == $k).display")
            current_focused_space_display=$(echo $current_focused_space_info | jq '.display')
#            echo "tmp_bind_space_display: $tmp_bind_space_display"
#            echo "current_focused_space_info.display: $current_focused_space_display"
            if [[ $tmp_bind_space_display == $current_focused_space_display ]]; then
              echo "Space $current_focused_space_index 和 Space $k 在同一个显示器，不用聚焦"
              continue
            fi
            # 如果 space $k 的 is-visible为true，不用聚焦
            tmp_bind_space_is_visible=$(echo $all_space_info | jq ".[] | select(."index" == $k).\"is-visible\"")
            if [[ $tmp_bind_space_is_visible == "true" ]]; then
              echo "Space $current_focused_space_index 和 Space $k 绑定，Space $k 已经可见，不用聚焦"
              continue
            fi
            echo "由于 Space $current_focused_space_index 和 Space $k 绑定，因此聚焦 Space $k"
            yabai -m space --focus $k
            let "focusChangeCount++"
          else
            break 3
          fi
        fi
      done
      if [[ $focusChangeCount -lt $maxFocusChangeCount ]]; then
        sleep 0.3
        # 如果focusChangeCount>0，说明已经聚焦过其他space，需要重新聚焦current_focused_space
        if [[ $focusChangeCount -gt 0 ]]; then
          echo "重新聚焦 Space $current_focused_space_index"
          yabai -m space --focus $current_focused_space_index
          let "focusChangeCount++"
        fi
      fi
    fi
  done
done
