import {closeMainWindow, LaunchProps} from "@raycast/api";
import {runYabaiCommand} from "./helpers";

export default async function Command(args: LaunchProps) {
    const padding = args.arguments.padding
    await closeMainWindow()
    await runYabaiCommand(`-m space --padding abs:46:10:${padding}:${padding}`)
}
