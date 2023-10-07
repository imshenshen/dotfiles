import {getPreferenceValues, List} from "@raycast/api";
import {useEffect, useState} from "react";
import {GroupedEntries, HistoryEntry, Preferences, Tab} from "./interfaces";
import {getOpenTabs} from "./actions";
import {ChromeListItems} from "./components";
import {useCachedState} from "@raycast/utils";
import {CHROME_PROFILE_KEY, DEFAULT_CHROME_PROFILE_ID} from "./constants";
import {useHistorySearch} from "./hooks/useHistorySearch";
import FuzzySearch from 'fuzzy-search';

const groupEntries = (allEntries?: HistoryEntry[]): GroupedEntries =>
    allEntries
        ? allEntries.reduce((acc, cur) => {
            const title = new Date(cur.lastVisited).toLocaleDateString(undefined, {
                weekday: "long",
                year: "numeric",
                month: "long",
                day: "numeric",
            });
            const groupEntries = acc.get(title) ?? [];
            groupEntries.push(cur);
            acc.set(title, groupEntries);
            return acc;
        }, new Map<string, HistoryEntry[]>())
        : new Map<string, HistoryEntry[]>();


export default function Command() {
    const [searchText, setSearchText] = useState<string>();
    const [profile] = useCachedState<string>(CHROME_PROFILE_KEY, DEFAULT_CHROME_PROFILE_ID);

    const {data: histories, isLoading, errorView, revalidate} = useHistorySearch(profile, searchText);


    const groupedEntries = groupEntries(histories);
    const groups = Array.from(groupedEntries.keys());

    const {useOriginalFavicon} = getPreferenceValues<Preferences>();
    const [tabs, setTabs] = useState<Tab[]>([]);

    async function getTabs() {
        setTabs(await getOpenTabs(useOriginalFavicon));
    }

    useEffect(() => {
        getTabs().then();
    }, []);

    const [tabsFuzzySearch, setTabsFuzzySearch] = useState<FuzzySearch<Tab> | null>(null)
    useEffect(() => {
        setTabsFuzzySearch(new FuzzySearch(tabs, ['title', 'url'], {caseSensitive: true}))
    }, [tabs]);

    const filteredTabs = tabsFuzzySearch ? tabsFuzzySearch.search(searchText) : tabs

    return (
        <List
            onSearchTextChange={setSearchText}
            isLoading={tabs.length === 0 || isLoading}
            throttle={true}

        >
            <List.Section title="Tabs" key="Tabs">
                {filteredTabs.map((tab) => (
                    <ChromeListItems.TabList
                        key={tab.key()}
                        tab={tab}
                        useOriginalFavicon={useOriginalFavicon}
                        onTabClosed={getTabs}
                    />
                ))}
            </List.Section>
            {groups?.map((group) => (
                <List.Section title={group} key={group}>
                    {groupedEntries?.get(group)?.map((e) => (
                        <ChromeListItems.TabHistory key={e.id} entry={e} profile={profile}/>
                    ))}
                </List.Section>
            ))}
        </List>
    );
}
