#!/usr/bin/env /usr/local/bin/node
/**
 * @see   GitLab API Documentation    https://docs.gitlab.com/ee/api/README.html
 * @see   Create GitLab Access Token  https://gitlab.com/profile/personal_access_tokens
 * @see   BitBar Node Module Docs     https://github.com/sindresorhus/bitbar
 */

const GITLAB_DOMAIN = 'git.jd.com'
const PRIVATE_TOKEN = ''
const MAX_LENGTH = 50

let bitbar
const fs = require('fs')
const path = require('path')
const SETTINGS_FILE_PATH = path.resolve(
  __dirname,
  './.gitlab_merge_requests.settings.json'
);


const gitlabIconBase64 =
  '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';

function request(path) {
  const httpTransport = require('https');
  const responseEncoding = 'utf8';
  const httpOptions = {
    hostname: GITLAB_DOMAIN,
    port: '443',
    path,
    method: 'GET',
    headers: { 'PRIVATE-TOKEN': PRIVATE_TOKEN }
  };
  httpOptions.headers['User-Agent'] =
    'bitbar/gitlab_projects - node ' + process.version;

  return new Promise((resolve, reject) => {
    const request = httpTransport
    .request(httpOptions, (res) => {
      let responseBufs = [];
      let responseStr = '';

      res
      .on('data', (chunk) => {
        if (Buffer.isBuffer(chunk)) {
          responseBufs.push(chunk);
        } else {
          responseStr = responseStr + chunk;
        }
      })
      .on('end', () => {
        if (responseBufs.length > 0) {
          responseStr = Buffer.concat(responseBufs).toString(responseEncoding);
        } else {
          responseStr = responseStr;
        }

        resolve(JSON.parse(responseStr));
      });
    })
    .setTimeout(0)
    .on('error', (error) => {
      reject(error);
    });
    request.write('');
    request.end();
  });
}

async function getTodos(){
  let todoList = await request('/api/v4/todos')

  let content = []
  content.push(`${todoList.length} Todos | image=${gitlabIconBase64}`)
  content.push('---')
  let todoContent = todoList.map(function(todo){
    //console.log(todo)
    //return `${`[${todo.target_type}][${todo.target.state}]${todo.author.name} ${todo.action_name} you on ${new Date(todo.created_at).toLocaleDateString()}`.padEnd(70,' ')}` + `${todo.body.substring(0,30).padEnd(33)} | href=${todo.target_url}`
    let title = `[${todo.target_type}] ${todo.body.substring(0,30).padEnd(33)} | href=${todo.target_url}\n`
    let subtitle = `[${todo.target.state}] ${todo.author.name} ${todo.action_name} you on ${new Date(todo.created_at).toLocaleDateString()}\n | size=12 color=blue`

    return `${title}${subtitle}---\n`
  })
  content = content.concat(todoContent)
  console.log(content.join('\n'))
}

getTodos().catch((error)=>{
  console.error(error)
})
