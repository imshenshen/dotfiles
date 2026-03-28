import { closeMainWindow, LaunchProps, showToast, Toast } from "@raycast/api";
import { runYabaiCommand } from "./helpers";
import { execaCommand } from "execa";
import { userInfo } from "os";

const { execSync } = require("child_process");
const fs = require("fs");
const os = require("os");

export default async function Command(args: LaunchProps) {
  let padding = args.arguments.padding;
  // padding 转换为数字，只有数字可用
  if (padding === undefined || isNaN(Number(padding))) {
    await showToast({
      title: "无效的参数",
      message: "padding 参数必须是数字",
      style: Toast.Style.Failure,
    });
    return;
  }
  padding = Number(padding);
  console.log("padding is ", padding, typeof padding);

  const { stdout } = await runYabaiCommand("-m query --spaces --space");
  // 使用jq解析JSON
  const spaceIndex = JSON.parse(stdout).index;

  const configPath = `${os.homedir()}/.config/yabai/spacePadding.conf`;
  // 读取现有配置
  let config = "";
  if (fs.existsSync(configPath)) {
    config = fs.readFileSync(configPath, "utf8").trim();
  }

  await closeMainWindow();

  // 将配置字符串转换为对象
  const paddingMap: Record<string, string> = {};
  if (config.length > 0) {
    config.split(",").forEach((pair) => {
      const [key, value] = pair.split(":");
      if (key && value) {
        paddingMap[key.trim()] = value.trim();
      }
    });
  }
  // 更新逻辑
  if (padding === 0) {
    delete paddingMap[spaceIndex];
  } else {
    paddingMap[spaceIndex] = padding;
  }
  // 重新组装配置字符串
  const newConfig = Object.entries(paddingMap)
    .map(([key, value]) => `${key}:${value}`)
    .join(",");

  // 写入配置文件
  fs.writeFileSync(configPath, newConfig + "\n", "utf8");
  // 执行命令 $HOME/.config/yabai/configSpace.sh
  try {
    const jjj = await execaCommand(`${os.homedir()}/.config/yabai/configSpace.sh`, {
      env: {
        ...process.env,
        USER: userInfo().username,
        PATH: "/bin:/usr/bin:/opt/homebrew/bin:/usr/local/bin:" + process.env.PATH,
      },
    }).catch(console.error);
    console.log('jj',jjj);
  } catch (error: any) {
    console.error("执行 configSpace.sh 失败：", error);
  }

  // console.log(`已更新 space ${spaceIndex} 的 padding 为 ${padding === 0 ? "删除" : padding}`);
}
