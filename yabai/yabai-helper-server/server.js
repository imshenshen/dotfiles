import express from 'express';
import {exec} from 'child_process';

const app = express();
const port = 3030;

// 使用JSON中间件解析POST请求的body
app.use(express.json());
// cors
app.use((req, res, next) => {
    res.header('Access-Control-Allow-Origin', req.headers.origin || '*');
    res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    next();
});

// 定义POST端点，用于接收yabai命令
app.post('/execute-yabai', (req, res) => {
    const {command} = req.body; // 从请求中提取命令

    if (!command) {
        res.status(400).json({error: 'Command not provided'});
        return;
    }

    // 仅允许以“yabai”开头的命令，防止潜在的安全风险
    if (!command.startsWith('yabai')) {
        res.status(403).json({error: 'Unauthorized command'});
        return;
    }

    // 执行yabai命令
    exec(command, (error, stdout, stderr) => {
        if (error) {
            res.status(500).json({error: `Execution error: ${error.message}`});
            return;
        }

        res.json({
            output: stdout.trim(),
            error: stderr.trim(),
        });
    });
});

// 启动HTTP服务器
app.listen(port, () => {
    console.log(`Server is running at http://localhost:${port}/`);
});
