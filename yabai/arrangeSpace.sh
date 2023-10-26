#!/bin/bash

LOCKFILE="/tmp/arrangeSpace.lock"

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

# 总 Space 数
wanted_space_count=8
display_2_space_count=0
display_3_space_count=0
# 如果有两个以上显示器，则设置副显示器上的 space 数量
if [ $display_count -eq 2 ]; then
  display_2_space_count=2
  display_3_space_count=0
elif [ $display_count -eq 3 ]; then
  display_2_space_count=1
  display_3_space_count=1
fi
first_display_space_count=$((wanted_space_count - display_2_space_count - display_3_space_count))

# 获取当前已有的空间数量
space_info=$(yabai -m query --spaces)
space_count=$(echo $space_info | jq '. | length')
current_focused_space=$(echo $space_info | jq '.[] | select(."has-focus" == true).index')

if [ $current_focused_space -ne 1 ]; then
  echo "当前在第一个空间，将第一个空间设置为焦点。"
  yabai -m space --focus 1
fi

# 计算需要添加或删除的空间数量
spaces_to_add_or_remove=$((wanted_space_count - space_count))
echo "当前有个 $space_count 空间，我需要 $wanted_space_count 个空间，将会添加/删除 $spaces_to_add_or_remove 个空间。"

if [ $spaces_to_add_or_remove -gt 0 ]; then
  # 添加空间
  for ((i=0; i<$spaces_to_add_or_remove; i++)); do
    yabai -m space --create
  done
  echo "已创建 $spaces_to_add_or_remove 个空间。"
fi

space_info=$(yabai -m query --spaces)
space_count=$(echo $space_info | jq '. | length')

# 由于每个Display至少有一个Space，删除时会报错，所以先排列一下Space， todo 这样会导致display1的space重排，需要再看看
echo "从0到space_count循环，从最后一个显示器开始，每个显示器保留一个Space，其他的放到第一个显示器"


for ((i=0; i<$space_count; i++)); do
  last_display_index=$((display_count - i))
  if [ $last_display_index -lt 1 ]; then
    last_display_index=1
  fi
  if [ $(yabai -m query --spaces | jq '.['$((space_count - i - 1 ))'].display')  -ne $last_display_index ]; then
    yabai -m space $((space_count - i)) --display $last_display_index
    echo "将空间 $((space_count - i)) 移动到第 $last_display_index 个显示器。"
  fi
done

if [ $spaces_to_add_or_remove -lt 0 ]; then
  # 删除多余的空间
  spaces_to_remove=$((0 - spaces_to_add_or_remove))
  spaces_to_remove_indexs=$(yabai -m query --spaces --display 1  | jq '.[-'$spaces_to_remove':] | reverse | .[].index')
  for space_index in $spaces_to_remove_indexs; do
    yabai -m space $space_index --destroy
    echo "已删除空间 $space_index"
  done
fi
# 现在Space为所需的数量，每个副显示器有一个Space，剩余的Space都在第一个显示器，接下来开始按需求移动Space，这样不会报错了
echo "按需求移动Space"
## 将前$first_display_space_count之后的$display_2_space_count个Space移动到第二个显示器
if [ $display_2_space_count -gt 0 ]; then
  for ((i=0; i<$display_2_space_count; i++)); do
    space_index=$((first_display_space_count + 1))
    if [ $(yabai -m query --spaces | jq '.['$((space_index-1))'].display') -ne 2 ]; then
      echo "将空间 $space_index 移动到第二个显示器。"
      yabai -m space $space_index --display 2
    fi
  done
fi
## 处理第三个显示器
if [ $display_3_space_count -gt 0 ]; then
  for ((i=0; i<$display_3_space_count; i++)); do
    space_index=$((first_display_space_count + display_2_space_count + 1))
    if [ $(yabai -m query --spaces | jq '.['$((space_index-1))'].display') -ne 3 ]; then
      echo "将空间 $space_index 移动到第三个显示器。"
      yabai -m space $space_index --display 3
    fi
  done
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
    if [ "$space_label" == '""' ]; then
      echo "设置space $space_index 的label为 ${labels[$i]}"
      yabai -m space "$space_index" --label "${labels[$i]}"
    fi
  done
}

# 为每个空间设置默认label
set_default_labels "$wanted_space_count"

first_display_width=$(echo $display_info | jq '.[0].frame.w')
first_display_width_int=$(printf "%.0f" $first_display_width | bc)


# 当first_display_width大于2800时，将space 3的布局设置为bsp；否则设置为stack
if [ $first_display_width_int -gt 2800 ]; then
  echo "第一个显示器的宽度 $first_display_width_int 大于2800，将space 3的布局设置为bsp。"
  yabai -m config --space 2 layout bsp
else
  echo "第一个显示器的宽度 $first_display_width_int 小于2800，将space 3的布局设置为stack。"
  yabai -m config --space 2 layout stack
fi

# const liuhaiping = { mbp14: [[1512,982],[1800*1169]] }
# 如果只有一个屏幕且宽小于等于1800的话，则将 top_padding 设置为 10
if [ $display_count -eq 1 ] && [ $first_display_width_int -le 1800 ]; then
  echo "只有一个屏幕且宽小于等于1800，将 top_padding 设置为 10。"
  yabai -m config top_padding 10
else
  yabai -m config top_padding 46
fi

osascript -e 'tell application id "tracesOf.Uebersicht" to refresh widget id "simple-bar-index-jsx"'

rm ${LOCKFILE}
