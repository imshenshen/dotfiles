import { run } from 'uebersicht';
import {defaultTheme} from './lib/style';

export const command = `/opt/homebrew/bin/yabai -m query --windows --space | /opt/homebrew/bin/jq '.[] | select(."has-focus"==true)'`

export const refreshFrequency = 2000

export const className = `
  ${defaultTheme}
  position: relative;
  float: right;
  display: flex;
`;

export const render = ({output, error}) => {
  let data = ""
  try {
    data = JSON.parse(output)
  }catch (e){
    console.log(e)
  }
  return data?(
    <div>{!data.floating?'🎯':'🎈'} {data.app} - {data.title.substring(0,15)}</div>
  ):(<div>no focused windows</div>);
}
