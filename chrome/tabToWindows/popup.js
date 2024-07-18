const windows = await chrome.windows.getAll({
    windowTypes: ['normal']
})
// new Map , key =  window.left|top|width|height, value = window
const windowMap = new Map();
for (const window of windows) {
    const key = `${window.left}|${window.top}|${window.width}|${window.height}`;
    windowMap.set(key, window);
}
const windowsInfo = []

const command = 'yabai -m query --windows'

const yabaiJSON = await chrome.runtime.sendMessage(
    {type: 'send_yabai_command', command},  // 向后台服务发送消息
);

if (yabaiJSON.error) {
    document.querySelector('ul').textContent = yabaiJSON.error
} else {
    const yabaiWindows = JSON.parse(yabaiJSON.output)

    for (const yabaiWindow of yabaiWindows) {
        if (yabaiWindow.app === 'Google Chrome') {
            const {x, y, w, h} = yabaiWindow.frame
            const key = `${x}|${y}|${w}|${h}`
            const info = windowMap.get(key)
            if (info && info.id && !info.focused) {
                windowsInfo.push(
                    {
                        yabaiInfo: yabaiWindow,
                        chromeInfo: info
                    }
                )
            }
        }
    }
    windowsInfo.sort((a, b) => a.yabaiInfo.space - b.yabaiInfo.space)
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
                <span class="space">${window.yabaiInfo.space}</span>
                <span class="title">${window.yabaiInfo.title}</span>
        `
        }

        element.addEventListener('click', async () => {
            const tabs = await chrome.tabs.query({
                currentWindow: true,
                highlighted: true
            });
            if (tabs.length) {
                await chrome.runtime.sendMessage({
                    type: 'moveToWindow',
                    windowId: window?.chromeInfo?.id,
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
            return window.yabaiInfo.title.toLowerCase().includes(query) || window.yabaiInfo.space.toString().startsWith(query)
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
