#!/bin/bash

LOCKFILE="/tmp/arrangeSpace.lock"

trap 'rm -f "${LOCKFILE}"; exit' EXIT

if [ -e ${LOCKFILE} ]; then
    exit 0
fi

touch ${LOCKFILE}

# 检查yabai命令是否可用
if ! command -v yabai &> /dev/null; then
  echo "yabai命令不存在，请确保已安装yabai窗口管理工具。"
  exit 1
fi

# 获取当前连接的显示器数量
display_info=$(yabai -m query --displays)
display_count=$(echo $display_info | jq '. | length')
echo "当前连接了 $display_count 个显示器。"

# 设置每个显示器上的 space 数量
declare -a wanted_display_space_count

if [ $display_count -eq 1 ]; then
  wanted_display_space_count=(8)
elif [ $display_count -eq 2 ]; then
  wanted_display_space_count=(6 2)
elif [ $display_count -eq 3 ]; then
  wanted_display_space_count=(6 1 1)
fi
total_wanted_space_count=0
echo "每个显示器想要的 space 数量为 ${wanted_display_space_count[@]}"

# 输出每个显示器上的 space 数量
for ((i=0; i<$display_count; i++)); do
  display_index=$((i + 1))
  total_wanted_space_count=$((total_wanted_space_count + ${wanted_display_space_count[$i]}))
done
echo "总共想要的 space 数量为 $total_wanted_space_count"

current_focused_space=$(yabai -m query --spaces | jq '.[] | select(."has-focus" == true).index')
if [ $current_focused_space -ne 1 ]; then
  echo "将第一个空间设置为焦点。"
  yabai -m space --focus 1
fi

# 由于移动、删除空间时空间中的窗口如何移动 有不确定性，因此只能每个显示器分别进行加减操作
# 对于每个显示器，少了就加；多了就从第一个多出来的空间开始依次向下一个显示器移动，如果没有下一个显示器，则删除
for ((i=0; i<$display_count; i++)); do
  display_index=$((i + 1))
  echo "处理第 $display_index 个显示器。"
  display_space_info=$(yabai -m query --spaces --display $display_index)
  display_space_count=$(echo $display_space_info | jq '. | length')
  echo "第 $display_index 个显示器有 $display_space_count 个空间。"

  if [ $display_space_count -lt ${wanted_display_space_count[$i]} ]; then
    # 如果当前显示器的空间数量少于所需数量，则添加空间
    spaces_to_add_count=$((${wanted_display_space_count[$i]} - display_space_count))
    for ((j=0; j<$spaces_to_add_count; j++)); do
      yabai -m space --create $display_index
    done
    echo "已为第 $display_index 个显示器添加 $spaces_to_add_count 个空间。"

  elif [ $display_space_count -gt ${wanted_display_space_count[$i]} ]; then
    first_space_index_of_display=$(echo $display_space_info | jq '.[0].index')
    remove_or_move_space_index=$((${wanted_display_space_count[$i]} + $first_space_index_of_display))
    spaces_to_remove_count=$((display_space_count - ${wanted_display_space_count[$i]}))
    for ((j=0;j<$spaces_to_remove_count; j++)); do
      # 判断是否为最后一个显示器
      if [ $display_index -eq $display_count ]; then
        yabai -m space $remove_or_move_space_index --destroy
      else
        yabai -m space $remove_or_move_space_index --display $(($display_index + 1))
      fi
    done
  fi
done


# 如果current_focused_space还存在的话，则将焦点设置为current_focused_space
if [[ $current_focused_space -ne 1 ]] && [[ $(yabai -m query --spaces | jq ".[${current_focused_space}]") ]]; then
  echo "将焦点设置为 $current_focused_space"
  yabai -m space --focus $current_focused_space
fi

# 函数: 为每个空间设置默认label
function set_default_labels {
  local wanted_space_count="$1"
  local space_info
  space_info=$(yabai -m query --spaces)
  local labels=("🌈 Main" "💬 Chat" "⌨️  Dev" "🏖 Free4" "🏖 Free5" "🎸 Media" "🏖 Free7" "🏖 Free8" "🏖 Free9")

  for i in $(seq 0 $((wanted_space_count - 1))); do
    local space_index
    space_index=$(echo "$space_info" | jq ".[$i].index")
    local space_label
    space_label=$(echo "$space_info" | jq ".[$i].label")
    # 判断space_label是否只包含数字 或者为空
    if [[ "$space_label" =~ ^[0-9]+$ ]] || [ "$space_label" == '""' ]; then
      echo "设置space $space_index 的label为 ${labels[$i]}"
      yabai -m space "$space_index" --label "${labels[$i]}"
    fi
  done
}

# 为每个空间设置默认label
set_default_labels "$total_wanted_space_count"

first_display_width=$(echo $display_info | jq '.[0].frame.w')
first_display_width_int=$(printf "%.0f" $first_display_width | bc)


# 当first_display_width大于2800时，将space 2 的布局设置为bsp；否则设置为stack
# if [ $first_display_width_int -gt 2800 ]; then
#   echo "第一个显示器的宽度 $first_display_width_int 大于2800，将space 2的布局设置为bsp。"
#   yabai -m config --space 2 layout bsp
# else
#   echo "第一个显示器的宽度 $first_display_width_int 小于2800，将space 2的布局设置为stack。"
#   yabai -m config --space 2 layout stack
# fi

# const liuhaiping = { mbp14: [[1512,982],[1800*1169]] }
# 如果只有一个屏幕且宽小于等于1800的话，则将 top_padding 设置为 10
if [ $display_count -eq 1 ] && [ $first_display_width_int -le 1800 ]; then
  echo "只有一个屏幕且宽小于等于1800，将 top_padding 设置为 10。"
  yabai -m config top_padding 46
else
  yabai -m config top_padding 46
fi

osascript -e 'tell application id "tracesOf.Uebersicht" to refresh widget id "simple-bar-index-jsx"'
