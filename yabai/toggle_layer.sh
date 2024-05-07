#!/bin/bash
current_window_info=$(yabai -m query --windows --window)
current_window_layer=$(echo $current_window_info | jq -r '."sub-layer"')
# toggle sub-layer with below and normal
echo "current sub-layer is $current_window_layer"
if [ "$current_window_layer" == "below" ]; then
  echo "set sub-layer to normal."
  yabai -m window --sub-layer normal
else
  echo "set sub-layer to below."
  yabai -m window --sub-layer below
fi
