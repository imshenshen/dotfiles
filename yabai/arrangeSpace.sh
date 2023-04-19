#!/bin/bash
# 检查yabai命令是否可用
if ! command -v yabai &> /dev/null; then
  echo "yabai命令不存在，请确保已安装yabai窗口管理工具。"
  exit 1
fi

# 获取has-focus为true的空间

current_space_id=$(yabai -m query --spaces | jq '.[] | select(."has-focus"==true) | .index')

# 获取当前已有的空间数量
space_count=$(yabai -m query --spaces | jq '. | length')

# 计算需要添加或删除的空间数量
spaces_to_add_or_remove=$((9 - space_count))

if [ $spaces_to_add_or_remove -gt 0 ]; then
  # 添加空间
  for ((i=0; i<$spaces_to_add_or_remove; i++)); do
    yabai -m space --create
  done
  echo "已创建 $spaces_to_add_or_remove 个空间。"
elif [ $spaces_to_add_or_remove -lt 0 ]; then
  # 删除多余的空间
  spaces_to_remove=$((0 - spaces_to_add_or_remove))
  spaces_to_remove_ids=$(yabai -m query --spaces | jq '.[-'$spaces_to_remove':] | .[].index')
  for space_id in $spaces_to_remove_ids; do
    yabai -m space $space_id --destroy
  done
  echo "已删除 $spaces_to_remove 个多余的空间。"
else
  echo "当前已有 9 个空间，无需添加或删除。"
fi

# 获取当前连接的显示器数量
display_count=$(yabai -m query --displays | jq '. | length')

if [ $display_count -ge 2 ]; then
  # 获取第二个显示器的id
#  second_display_id=$(yabai -m query --displays | jq '.[1].index')
  second_display_id=2

  # 获取第一个显示器的id
#  first_display_id=$(yabai -m query --displays | jq '.[0].index')
  first_display_id=1

  # 获取显示器上的所有空间id
  first_display_space_ids=$(yabai -m query --spaces | jq '.[].index' | head -n 7)

  # 将第一个显示器上的所有空间移动到第一个显示器
  for space_id in $first_display_space_ids; do
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

  echo "已将最后两个空间移动到第二个显示器。"
else
  echo "当前只有一个显示器，无需移动空间。"
fi

# Space 1 主屏幕
yabai -m space 1 --label "🌈 Main"

# Space2 开发用的，Microsoft Edge用来开发，以及一些IDE
yabai -m space 2 --label "⌨️  Dev"

# Space 3 ：沟通用
yabai -m space 3 --label "💬 Chat"

# Space 4-6 备用
yabai -m space 4 --label "🏖 Free"
yabai -m space 5 --label "🏖 Free2"
yabai -m space 6 --label "🏖 Free3"
yabai -m space 7 --label "🎸 Media"

# 在副屏上用
yabai -m space 8 --label "🎈 Sec"
yabai -m space 9 --label "🎈 Sec2"
