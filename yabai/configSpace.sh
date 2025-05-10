#!/bin/bash

LOCKFILE="/tmp/configSpace.lock"

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
# 获取当前yabai的padding

# 1. 根据 window 的数量来调整 Space 的 Padding
# 获取当前聚焦的space
current_space_info=$(yabai -m query --spaces --space)
current_space_id=$(echo $current_space_info | jq '.index')
current_space_display=$(echo $current_space_info | jq '.display')

# 从文件 $HOME/.config/yabai/spacePadding.conf 获取当前有没有设置固定的padding，spacePadding.conf的结构为 spaceIndex:padding,spaceIndex:padding,...
# 例如 1:10,2:20,3:30
force_padding=$(cat $HOME/.config/yabai/spacePadding.conf 2>/dev/null)
force_padding=$(echo $force_padding | tr ',' ' ') # 去除空格
if [ -n "$force_padding" ]; then
  for padding in $force_padding; do
    space_index=$(echo $padding | cut -d':' -f1)
    space_padding=$(echo $padding | cut -d':' -f2)
    if [ "$space_index" == "$current_space_id" ]; then
      yabai -m space --padding abs:46:10:$space_padding:$space_padding
      echo "YABAI_SPACE_PADDING 有设置 padding 为 $space_padding"
      exit 0
    fi
  done
fi


# 检查 current_space_display 的宽高比是否大于2
current_display_info=$(yabai -m query --displays --display $current_space_display)
display_width=$(echo $current_display_info | jq '.frame.w | round')
display_ratio=$(echo $current_display_info | jq '.frame | (.w)/(.h) | round')
if [ $display_ratio -ge 2 -a $display_width -gt 3010 ]; then
#  echo "当前Space $current_space_id 所在显示器 $current_space_display 屏幕宽 $display_width ,比例 $display_ratio  ，根据窗口数量设置padding"
  # 检查当前space的窗口数量
  current_space_window_count=$(yabai -m query --windows --space $current_space_id | jq '[.[] | select(."is-visible"==true and ."is-floating"==false)] | length')
  echo "当前space有 $current_space_window_count 个可见的非floating窗口。"
  if [ $current_space_window_count -eq 1 ]; then
    # x 设置为 宽度的1/3
    x_padding=$(($display_width/4))
    yabai -m space --padding abs:46:30:$x_padding:$x_padding
    echo "设置padding为 $x_padding"
  elif [ $current_space_window_count -eq 2 ]; then
    # x 设置为 宽度的1/8
    x_padding=$(($display_width/10))
    yabai -m space --padding abs:46:30:$x_padding:$x_padding
    echo "设置padding为 $x_padding"
  # 其他状况padding为10
  else
    yabai -m space --padding abs:46:30:10:10
    echo "设置padding为 10"
  fi
else
  yabai -m space --padding abs:46:30:10:10
fi


# 2.
