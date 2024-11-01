const windows = await chrome.windows.getAll({
    windowTypes: ['normal']
})

const allTabs = await chrome.tabs.query({})
let queryOptions = {active: true, lastFocusedWindow: true};
// `tab` will either be a `tabs.Tab` instance or `undefined`.
let [tab] = await chrome.tabs.query(queryOptions);
const currentTab = tab

const windowsInfo = []

const command = `aerospace list-windows --all --format ["%{app-name}",%{window-id},"%{window-title}",%{workspace}]`

const yabaiJSON = await chrome.runtime.sendMessage(
    {type: 'send_yabai_command', command},  // 向后台服务发送消息
);
console.log('yabaiJSON', yabaiJSON)
if (yabaiJSON?.error) {
    document.querySelector('ul').textContent = yabaiJSON.error
} else {
    let text = yabaiJSON.output.replaceAll(']\n', '],');
    const windowss = JSON.parse(`[${text}]`)

    for (const item of windowss) {
        if (item[0] === 'Google Chrome' && !item[2].startsWith('DevTools')) {
            if (currentTab) {
                console.log('currentTab', currentTab)
            }
            windowsInfo.push(item)
        }
    }
    windowsInfo.sort((a, b) => a[3] - b[3])
    renderWindows(windowsInfo)
}

function renderWindows(windowsInfo) {
    const elements = new Set();
    for (let i = 0; i <= windowsInfo.length; i++) {
        const window = windowsInfo[i];
        // 构建一个 li > div.title > span.space
        const element = document.createElement('li');
        element.classList.add('windowItem');
        if (i === 0) {
            element.classList.add('active')
        }

        if (!window) {
            element.innerHTML = `
                <span class="space">+</span>
                <span class="title">新窗口</span>
            `
        } else {
            element.innerHTML = `
                <span class="space">${window[3]}</span>
                <span class="title">${window[2]}</span>
        `
        }

        element.addEventListener('click', async () => {
            const tabs = await chrome.tabs.query({
                currentWindow: true,
                highlighted: true
            });
            if (tabs.length) {
                let windowId = allTabs.find(tab => window[2].startsWith(tab.title))?.windowId
                await chrome.runtime.sendMessage({
                    type: 'moveToWindow',
                    windowId: windowId,
                    tabs
                })
                // await moveToWindow(window.chromeInfo.id, tabs)
            }
        })
        elements.add(element);
    }
    document.querySelector('.windowsList').replaceChildren(...elements)
}

let inputEl = document.querySelector('#queryInput');
inputEl.addEventListener('input', (event) => {
    const query = event.target.value.trim().toLowerCase()
    if (query) {
        renderWindows(windowsInfo.filter(window => {
            return window[2].toLowerCase().includes(query) || window[3].toString().startsWith(query)
        }))
    } else {
        renderWindows(windowsInfo)
    }
})

// 添加选择事件，键盘上、下、ctrl+p、ctrl+n时，选中上一个、下一个
document.addEventListener('keydown', (event) => {
    const {key, ctrlKey} = event
    if (key === 'ArrowUp' || (ctrlKey && key === 'p')) {
        const current = document.querySelector('.windowItem.active')
        if (current) {
            const previous = current.previousElementSibling
            if (previous) {
                current.classList.remove('active')
                previous.classList.add('active')
            }
        } else {
            const last = document.querySelector('.windowItem:last-child')
            if (last) {
                last.classList.add('active')
            }
        }
    } else if (key === 'ArrowDown' || (ctrlKey && key === 'n')) {
        const current = document.querySelector('.windowItem.active')
        if (current) {
            const next = current.nextElementSibling
            if (next) {
                current.classList.remove('active')
                next.classList.add('active')
            }
        } else {
            const first = document.querySelector('.windowItem:first-child')
            if (first) {
                first.classList.add('active')
            }
        }
    } else if (key === 'Enter') {
        const current = document.querySelector('.windowItem.active')
        if (current) {
            current.click()
        }
    } else if (key === 'Escape') {
        window.close()
    }
})
//捕获阶段如果是正常的文字输入，则让Input先获取焦点
document.addEventListener('keydown', (event) => {
    const {key} = event
    if (key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey && !event.shiftKey) {
        inputEl.focus()
    }
}, true)
