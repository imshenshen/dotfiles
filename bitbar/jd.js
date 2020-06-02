#!/usr/bin/env /usr/local/bin/node

const fs = require('fs')
const path = require('path')
const exec = require('child_process').execSync

const bizhiPath = '/Users/caowenlong1/Documents/shenshen/bizhi'

if(process.argv.length<3){
  const files = fs.readdirSync(bizhiPath)
  let content = ['JD小工具','---']

  content.push('切换壁纸')
  for (let i=0;i<files.length;i++){
    let picName = files[i]
    if(!picName.startsWith('.')){
      content.push(`--${picName} |terminal=false bash="${process.argv[1]}" param1="bizhi" param2="'${path.resolve(bizhiPath,picName)}'"`)
    }
  }

  const omniPlanPath = '/Users/caowenlong1/Documents/jd/projects'
  content = content.concat(['---','OmniPlan文件'])
  const omniPlanFiles = fs.readdirSync(omniPlanPath,{withFileTypes:true})
  omniPlanFiles.forEach(function(dirent,index){
    let info  = fs.statSync(omniPlanPath + '/' + dirent.name)
    if(!dirent.name.endsWith('oplx') && info.isDirectory()){
      content.push(`--${dirent.name} |terminal=false bash="${process.argv[1]}" param1="openfile" param2="${path.resolve(omniPlanPath,dirent.name)}"`)
    }
  })
  //content.push(`--cloudaiot-fe |terminal=false bash="${process.argv[1]}" param1="openfile" param2="${path.resolve(omniPlanPath,'cloudaiot-fe')}"`)
  console.log(content.join('\n'))
}else{
  let command = process.argv[2]
  switch (command) {
    case 'bizhi':
      exec(`echo '' | sudo -S cp '${process.argv[3]}' '/Library/Desktop Pictures/Desktop201810.JPG'`)
      exec("killall Dock")
      break
    case 'openfile':
      exec(`open ${process.argv[3]}`)
      break
  }
}
