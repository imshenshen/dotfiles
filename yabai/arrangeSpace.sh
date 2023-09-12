#!/bin/bash

# 检查yabai命令是否可用
if ! command -v yabai &> /dev/null; then
  echo "yabai命令不存在，请确保已安装yabai窗口管理工具。"
  exit 1
fi
yabai -m space --focus 1

wanted_space_count=9

# 获取当前已有的空间数量
space_count=$(yabai -m query --spaces | jq '. | length')

# 计算需要添加或删除的空间数量
spaces_to_add_or_remove=$((wanted_space_count - space_count))

if [ $spaces_to_add_or_remove -gt 0 ]; then
  # 添加空间
  for ((i=0; i<$spaces_to_add_or_remove; i++)); do
    yabai -m space --create
  done
  echo "已创建 $spaces_to_add_or_remove 个空间。"
elif [ $spaces_to_add_or_remove -lt 0 ]; then
  # 删除多余的空间
  spaces_to_remove=$((0 - spaces_to_add_or_remove))
  spaces_to_remove_ids=$(yabai -m query --spaces | jq '.[-'$spaces_to_remove':] | reverse | .[].index')
  for space_id in $spaces_to_remove_ids; do
    yabai -m space $space_id --destroy
    echo "已删除空间 $space_id"
  done
  echo "已删除 $spaces_to_remove 个多余的空间。"
else
  echo "当前已有 9 个空间，无需添加或删除。"
fi

# 获取当前连接的显示器数量
display_info=$(yabai -m query --displays)
display_count=$(echo $display_info | jq '. | length')
first_display_width=$(echo $display_info | jq '.[0].frame.w')
# 当有1个显示器时，1-9都在第一个显示器上
# 当有2个显示器时，1-7在第一个显示器，8-9在第二个显示器
if [ $display_count -ge 2 ]; then
  second_display_id=2
  first_display_id=1

  # 获取显示器上的所有space取前7个
  first_7_space_ids=$(yabai -m query --spaces | jq '.[].index' | head -n 7)

  # 将第一个显示器上的所有空间移动到第一个显示器
  for space_id in $first_7_space_ids; do
    echo "将空间 $space_id 移动到第一个显示器。"
    yabai -m space $space_id --display $first_display_id
  done

  # 获取最后两个空间的id
  last_two_spaces_ids=$(yabai -m query --spaces | jq '.[-2:] | .[].index')

  # 将最后两个空间移动到第二个显示器
  for space_id in $last_two_spaces_ids; do
    echo "将空间 $space_id 移动到第二个显示器。"
    yabai -m space $space_id --display $second_display_id
  done
else
  echo "当前只有一个显示器，无需移动空间。"
fi

# 为每个space设置默认label
space_info=$(yabai -m query --spaces)
## 循环遍历每个space，为label为空的space都设置默认值：space 1的label为"🌈 Main"; space 2的label为"⌨️  Dev"; space 3的label为"💬 Chat"; space 4-6的label为"🏖 Free"; space 7的label为"🎸 Media"; space 8的label为"🎈 Sec"; space 9的label为"🎈 Sec2"
for i in $(seq 0 $(($wanted_space_count - 1))); do
  space_id=$(echo $space_info | jq ".[$i].index")
  space_label=$(echo $space_info | jq ".[$i].label")
  echo "space $space_id 的label为 $space_label"
  if [ "$space_label" == '""' ]; then
    case $space_id in
      1)
        yabai -m space $space_id --label "🌈 Main"
        echo "设置space $space_id 的label为 🌈 Main"
        ;;
      2)
        yabai -m space $space_id --label "⌨️  Dev"
        echo "设置space $space_id 的label为 ⌨️  Dev"
        ;;
      3)
        yabai -m space $space_id --label "💬 Chat"
        echo "设置space $space_id 的label为 💬 Chat"
        ;;
      4)
        yabai -m space $space_id --label "🏖 Free"
        echo "设置space $space_id 的label为 🏖 Free"
        ;;
      5)
        yabai -m space $space_id --label "🏖 Free2"
        echo "设置space $space_id 的label为 🏖 Free2"
        ;;
      6)
        yabai -m space $space_id --label "🏖 Free3"
        echo "设置space $space_id 的label为 🏖 Free3"
        ;;
      7)
        yabai -m space $space_id --label "🎸 Media"
        echo "设置space $space_id 的label为 🎸 Media"
        ;;
      8)
        yabai -m space $space_id --label "🎈 Sec"
        echo "设置space $space_id 的label为 🎈 Sec"
        ;;
      9)
        yabai -m space $space_id --label "🎈 Sec2"
        echo "设置space $space_id 的label为 🎈 Sec2"
        ;;
    esac
  fi
done
# 当first_display_width大于2800时，将space 3的布局设置为bsp；否则设置为stack
if [ $first_display_width -gt 2800 ]; then
  echo "第一个显示器的宽度大于2800，将space 3的布局设置为bsp。"
  yabai -m config --space 3 layout bsp
else
  echo "第一个显示器的宽度小于2800，将space 3的布局设置为bsp。"
  yabai -m config --space 3 layout stack
fi
osascript -e 'tell application id "tracesOf.Uebersicht" to refresh widget id "simple-bar-index-jsx"'



# Space 1 主屏幕
#yabai -m space 1 --label "🌈 Main"

# Space2 开发用的，Microsoft Edge用来开发，以及一些IDE
#yabai -m space 2 --label "⌨️  Dev"

# Space 3 ：沟通用
#yabai -m space 3 --label "💬 Chat"

# Space 4-6 备用
#yabai -m space 4 --label "🏖 Free"
#yabai -m space 5 --label "🏖 Free2"
#yabai -m space 6 --label "🏖 Free3"
#yabai -m space 7 --label "🎸 Media"

# 在副屏上用
#yabai -m space 8 --label "🎈 Sec"
#yabai -m space 9 --label "🎈 Sec2"
