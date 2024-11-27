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

# 筛选左边的窗口：x 坐标小于当前窗口的窗口
left_window=$(echo "$all_windows" | jq -c ".[] | select(.id != $current_id and .frame.x < $current_x)" \
  | jq -s '.' \
  | jq -c "sort_by(.frame.x) | reverse | .[0]")

# 如果没有找到左边的窗口，则选最右边的窗口
if [ -z "$left_window" ] || [ "$left_window" == "null" ]; then
  echo "node left window found."
  rightmost_window=$(echo "$all_windows" | jq -c ".[] | select(.id != $current_id)" \
    | jq -s '.' \
    | jq -c "sort_by(.frame.x) | reverse | .[0]")
  if [ -z "$rightmost_window" ]; then
    echo "No window to focus."
    exit 0
  fi
  echo "No window on the left. Focusing the rightmost window. window id is $(echo "$rightmost_window" | jq -r '.id')"
  target_window_id=$(echo "$rightmost_window" | jq -r '.id')
else
  echo "Focusing the left window. window id is $(echo "$left_window" | jq -r '.id')"
  target_window_id=$(echo "$left_window" | jq -r '.id')
fi

# 聚焦目标窗口
yabai -m window --focus "$target_window_id"

echo "Focused window with ID $target_window_id."
