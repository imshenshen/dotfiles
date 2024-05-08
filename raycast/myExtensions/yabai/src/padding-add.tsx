import {closeMainWindow, LaunchProps} from "@raycast/api";
import {runYabaiCommand} from "./helpers";

export default async function Command(args: LaunchProps) {
    const padding = args.arguments.padding || 100
    await closeMainWindow()
    await runYabaiCommand(`-m space --padding rel:0:0:${padding}:${padding}`)
}
