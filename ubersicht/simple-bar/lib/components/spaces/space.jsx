import * as Uebersicht from "uebersicht";
import OpenedApps from "./opened-apps.jsx";
import SpaceOptions from "./space-options.jsx";
import * as Utils from "../../utils";
import * as Yabai from "../../yabai";
import * as Settings from "../../settings";

const settings = Settings.get();

const Space = ({
  space,
  display,
  windows,
  displayIndex,
  currentSpaceIndex,
  SIPDisabled,
  lastOfSpace,
  showIndex
}) => {
  const labelRef = Uebersicht.React.useRef();
  const [hovered, setHovered] = Uebersicht.React.useState(false);
  const [noDelay, setNoDelay] = Uebersicht.React.useState(false);
  const [editable, setEditable] = Uebersicht.React.useState(false);
  const {
    index,
    label,
    "has-focus": hasFocus,
    focused: __legacyHasFocus,
    "is-visible": isVisible,
    visible: __legacyIsVisible,
    "is-native-fullscreen": isNativeFullscreen,
    "native-fullscreen": __legacyIsNativeFullscreen,
    type,
  } = space;
  const [spaceLabel, setSpaceLabel] = Uebersicht.React.useState(
    label?.length ? label : index
  );

  const { spacesDisplay } = settings;
  const {
    displayAllSpacesOnAllScreens,
    exclusionsAsRegex,
    displayStickyWindowsSeparately,
    hideDuplicateAppsInSpaces,
    showOptionsOnHover,
  } = spacesDisplay;
  if (!displayAllSpacesOnAllScreens && display !== space.display) return null;

  const exclusions = exclusionsAsRegex
    ? spacesDisplay.exclusions
    : spacesDisplay.exclusions.split(", ");
  const titleExclusions = exclusionsAsRegex
    ? spacesDisplay.titleExclusions
    : spacesDisplay.titleExclusions.split(", ");

  const onMouseEnter = (e) => {
    if (!showOptionsOnHover) return;
    const { altKey, metaKey } = e;
    if (altKey) return;
    setHovered(true);
    if (metaKey) setNoDelay(true);
  };
  const onMouseLeave = () => {
    setHovered(false);
    setNoDelay(false);
    setEditable(false);
    window.getSelection().removeAllRanges();
  };
  const onClick = (e) => {
    onMouseLeave(e);
    if (e.altKey) {
      setEditable(true);
      labelRef.current?.select();
      return;
    }
    if (hasFocus || __legacyHasFocus) return;
    if (SIPDisabled && !spacesDisplay.switchSpacesWithoutYabai) {
      Yabai.goToSpace(index);
      return;
    }
    Utils.switchSpace(currentSpaceIndex, index);
    Utils.clickEffect(e);
  };
  const onRightClick = (e) => {
    setHovered(true);
    setNoDelay(true);
  };
  const onChange = (e) => {
    if (!editable) return;
    const newLabel = e.target.value;
    setSpaceLabel(newLabel);
    Yabai.renameSpace(index, newLabel);
  };
  const onKeyPress = (e) => {
    if (e.key === "Enter") {
      setEditable(false);
      window.getSelection().removeAllRanges();
    }
  }

  const { nonStickyWindows: apps, stickyWindows } =
    Utils.stickyWindowWorkaround({
      windows,
      uniqueApps: hideDuplicateAppsInSpaces,
      currentDisplay: display,
      currentSpace: index,
      exclusions,
      titleExclusions,
      exclusionsAsRegex,
    });
  const allApps = [...apps, ...stickyWindows];

  if (
    !(hasFocus ?? __legacyHasFocus) &&
    !(isVisible ?? __legacyHasFocus) &&
    !allApps.length &&
    spacesDisplay.hideEmptySpaces
  )
    return null;

  const classes = Utils.classnames(`space space--${type}`, {
    "space--focused": hasFocus ?? __legacyHasFocus,
    "space--visible": isVisible ?? __legacyIsVisible,
    "space--fullscreen": isNativeFullscreen ?? __legacyIsNativeFullscreen,
    "space--hovered": hovered,
    "space--no-delay": noDelay,
    "space--empty": allApps.length,
    "space--editable": editable,
  });

  const labelSize = (
    typeof spaceLabel === "number" ? spaceLabel.toString() : spaceLabel
  ).length + 4;

  let hint = '';
  switch (index){
    case 1: hint = 'Q'; break;
    case 2: hint = 'W'; break;
    case 3: hint = 'E'; break;
    case 4: hint = 'R'; break;
    case 5: hint = 'T'; break;
    case 6: hint = 'Y'; break;
    case 7: hint = 'U'; break;
    case 8: hint = 'I'; break;
    case 9: hint = 'O'; break;
  }

  return (
    <Uebersicht.React.Fragment>
      {spacesDisplay.displayAllSpacesOnAllScreens && lastOfSpace && (
        <div className="spaces__separator" />
      )}
      <div
        className={classes}
        onMouseLeave={onMouseLeave}
        onMouseEnter={onMouseEnter}
      >
        <button
          className="space__inner"
          onClick={onClick}
          onContextMenu={onRightClick}
        >
          { showIndex && (<span className="space__index">{hint}</span>)}
          <input
            ref={labelRef}
            type="text"
            className="space__label"
            onChange={onChange}
            autoComplete="off"
            autoCorrect="off"
            spellCheck="false"
            autoCapitalize="off"
            onKeyUp={onKeyPress}
            value={spaceLabel}
            style={{ width: editable? '300px' : `${labelSize}ch` }}
            readOnly={!editable}
          />
          {/*<OpenedApps apps={displayStickyWindowsSeparately ? apps : allApps} />*/}
        </button>
        {SIPDisabled && (
          <SpaceOptions
            index={index}
            setHovered={setHovered}
            displayIndex={displayIndex}
          />
        )}
      </div>
    </Uebersicht.React.Fragment>
  );
};

export default Space;
