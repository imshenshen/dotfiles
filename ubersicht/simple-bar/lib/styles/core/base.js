// 小于1800的认为是刘海屏，左右间距变大，图标隐藏
const baseStyles = /* css */ `
.simple-bar {
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  z-index: 0;
  height: var(--bar-height);
  display: flex;
  gap: 16px;
  justify-content: center;
  align-items: stretch;
  padding: var(--bar-inner-margin);
  box-sizing: border-box;
  color: var(--foreground);
  font-size: var(--font-size);
  font-family: var(--font);
  background-color: var(--background);
  box-shadow: var(--light-shadow);
}

@media (max-width: 1800px) {
    .simple-bar {
        justify-content: space-between;
    }
    .simple-bar .spaces {
        max-width: 42vw;
    }
    .simple-bar .spaces .space__icon {
        display: none;
    }
}

.simple-bar--floating {
  top: 5px;
}
.simple-bar--no-bar-background {
  padding: 0;
  margin: 8px;
  width: calc(100% - 16px);
}
.simple-bar--on-bottom {
  top: unset;
  bottom: 0;
}
.simple-bar--floating.simple-bar--on-bottom {
  bottom: 5px;
}
.simple-bar--floating {
  left: 5px;
  width: calc(100% - 10px);
  border-radius: var(--bar-radius);
}
.simple-bar--no-bar-background,
.simple-bar--no-shadow {
  box-shadow: none;
}
.simple-bar--focused,
.simple-bar--no-shadow.simple-bar--focused {
  box-shadow: inset 0 0 0 1px var(--red);
}
.simple-bar--no-bar-background {
  background-color: transparent;
}
.simple-bar--no-color-in-data {
  color: var(--white);
}
.simple-bar--empty {
  height: var(--bar-height);
  display: flex;
  align-items: center;
}
.simple-bar--empty {
  z-index: 2;
}
.simple-bar--empty > span {
  position: relative;
  display: flex;
  align-items: center;
  color: var(--foreground);
}
.simple-bar--empty > span::before {
  content: "";
  width: 6px;
  height: 6px;
  margin-right: 7px;
  background-color: var(--red);
  border-radius: 50%;
}
.simple-bar--empty.simple-bar--loading > span::before {
  background-color: var(--green);
}
.simple-bar__data {
  display: flex;
  align-items: stretch;
}
#simple-bar-click-effect {
  position: absolute;
  border-radius: 50%;
  pointer-events: none;
  touch-action: none;
  background-color: var(--click-effect);
  z-index: 2147483647;
}
`;

export { baseStyles as styles };
