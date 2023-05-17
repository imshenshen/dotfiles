local opt = vim.opt

opt.clipboard = ""

--[[ 已经把tab映射给了cmp的tab，所以这里不需要再映射给copilot, copilot插件会自动检测cmp的tab映射并覆盖
https://github.com/github/copilot.vim/blob/1358e8e45ecedc53daf971924a0541ddf6224faf/plugin/copilot.vim#L23 ]]
vim.g.copilot_assume_mapped = true
