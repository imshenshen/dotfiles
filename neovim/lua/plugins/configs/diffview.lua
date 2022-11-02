local present, diffview = pcall(require, "diffview")

if not present then
  return
end

local options = {}

diffview.setup(options)
