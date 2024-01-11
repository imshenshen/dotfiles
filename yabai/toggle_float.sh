# 拿到当前Space中float的window的数量 和 8 的 余数
current_float_window_count=$(yabai -m query --windows --space | jq 'map(select(."is-floating" == true)) | length')
echo "当前Space中float的window的数量为 $current_float_window_count"
level=$((current_float_window_count % 4))
echo "level 为 $level"

# <rows>:<cols>:<start-x>:<start-y>:<width>:<height>
yabai -m window --toggle float
yabai -m window --grid 30:50:$(( 10 + $level )):$(( 1 + $level )):30:25
