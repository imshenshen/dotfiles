import { closeMainWindow, showHUD } from "@raycast/api";
import { createNewWindow } from "./actions";

export default async function Command() {
  try {
    await closeMainWindow();
    await createNewWindow();
  } catch (e){
    console.log(e)
    await showHUD("❌ Failed opening a new Google Chrome window");
  }
}
