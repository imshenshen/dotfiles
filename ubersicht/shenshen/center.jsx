import { run } from 'uebersicht';
import {defaultTheme} from './lib/style';

export const command = `yabai -m query --windows --space | jq '.[] | select(."has-focus"==true)'`

export const refreshFrequency = 2000

export const className = `
  ${defaultTheme}
  display: flex;
  float: right;
  margin-right: 40%;
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
