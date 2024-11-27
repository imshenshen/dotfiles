#!/bin/bash

# 检查 yabai 是否正在运行
if ! pgrep -x "yabai" > /dev/null; then
  echo "Yabai is not running. Please start yabai first."
  exit 1
fi

# 获取当前窗口的信息
current_window=$(yabai -m query --windows --window)
if [ -z "$current_window" ]; then
  echo "Failed to get current window."
  exit 1
fi

current_id=$(echo "$current_window" | jq -r '.id')
current_x=$(echo "$current_window" | jq -r '.frame.x')

# 查询当前空间上的所有窗口
all_windows=$(yabai -m query --windows --space | jq -c '[.[] | select(."is-visible" == true)]')

# 筛选右边的窗口：x 坐标大于当前窗口的窗口
right_window=$(echo "$all_windows" | jq -c ".[] | select(.id != $current_id and .frame.x > $current_x)" \
  | jq -s '.' \
  | jq -c "sort_by(.frame.x) | .[0]")

# 如果没有找到右边的窗口，则选最左边的窗口
if [ -z "$right_window" ] || [ "$right_window" == "null" ]; then
  leftmost_window=$(echo "$all_windows" | jq -c ".[] | select(.id != $current_id)" \
    | jq -s '.' \
    | jq -c "sort_by(.frame.x) | .[0]")
  if [ -z "$leftmost_window" ] || [ "$leftmost_window" == "null" ]; then
    echo "No valid window to focus."
    exit 0
  fi
  target_window_id=$(echo "$leftmost_window" | jq -r '.id')
else
  target_window_id=$(echo "$right_window" | jq -r '.id')
fi

# 检查目标窗口 ID 是否有效
if [ -z "$target_window_id" ] || [ "$target_window_id" == "null" ]; then
  echo "Failed to find a valid target window."
  exit 1
fi

# 聚焦目标窗口
yabai -m window --focus "$target_window_id"
echo "Focused window with ID $target_window_id (right)."
