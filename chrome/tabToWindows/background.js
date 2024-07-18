chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.type === 'send_yabai_command') {
        const command = message.command;
        const url = 'http://localhost:3030/execute-yabai';

        fetch(url, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({command})  // 将命令发送到服务器
        })
            .then(response => response.json())
            .then(data => {
                console.log('Command output:', data);
                sendResponse(data);  // 返回响应给发送方
            })
            .catch(error => {
                console.error('Error sending command:', error);
                sendResponse({error: error.message});
            });

        // 指示异步响应
        return true;
    } else if (message.type === 'moveToWindow') {
        const {windowId, tabs} = message;
        if (tabs.length) {
            if (windowId) {
                chrome.tabs.move(tabs.map(tab => tab.id), {
                    windowId: windowId,
                    index: -1
                }, () => {
                    chrome.tabs.update(tabs[0].id, {active: true}, function () {
                        chrome.windows.update(windowId, {focused: true});
                    });
                })
            } else {
                //create new window
                const activeTabIndex = tabs.findIndex(tab => tab.active);
                const activeTab = tabs.splice(activeTabIndex, 1)[0];

                chrome.windows.create({focused: true, tabId: activeTab.id}, (window) => {
                    if (tabs.length) {
                        chrome.tabs.move(tabs.map(tab => tab.id), {
                            windowId: window.id,
                            index: -1
                        })
                    }
                });
            }
        }

    }
});
