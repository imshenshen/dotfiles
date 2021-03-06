import getSpacesForDisplay from './lib/getSpacesForDisplay';
import {css, run} from 'uebersicht';
import {defaultTheme} from './lib/style';

export const initialState = {
  spaces: [],
  focused: 0,
};

export const command = `yabai -m query --spaces --display 1`

export const refreshFrequency = false;

export const className = `
  ${defaultTheme}
  margin-left: 10px;
  float: left;
  display: flex;
  padding: 0;
  div:first-of-type {
    border-top-left-radius: 3px;
    border-bottom-left-radius: 3px;
  }
  div:last-of-type {
    border-top-right-radius: 3px;
    border-bottom-right-radius: 3px;
  }
`;

const spaceClass = css`
  padding: 0 2ch;
  position: relative;
`;

const spaceFocusedClass = css`
  ${spaceClass}
  background-color: #81A1C1;
  color: #2e3440;
`;

const indexClass = css`
  font-size: 10px;
  height: 12px;
  line-height: 12px;
  position: absolute;
  right: 5px;
  top: 2px;
`;


export const render = ({output,error},dispatch) =>{
  let data = ""
  try {
    data = JSON.parse(output)
  }catch (e){
    console.log(e)
  }
  if(!data){
    return ''
  }
  return data.map(space => (
  <div
    key={space.index}
    className={space.focused ? spaceFocusedClass : spaceClass}>
    {space.label ? space.label : space.index}
    {space.label && <span className={indexClass}>{space.index}</span>}
  </div>
  ));
}

