refreshFrequency: false
# app加载main.css有Bug，先自己引入
render: () ->
    return '''
        <link rel="stylesheet" type="text/css" href="/shenshen/main2.css">
    '''
