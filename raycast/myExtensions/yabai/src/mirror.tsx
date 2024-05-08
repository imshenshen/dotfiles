import {closeMainWindow, LaunchProps} from "@raycast/api";
import {runYabaiCommand} from "./helpers";

export default async function Command(args: LaunchProps) {
    const type = args.arguments.type || 'y'
    await closeMainWindow()
    await runYabaiCommand(`-m space --mirror ${type}-axis`)
}
