" Basics {
    set shell=/bin/sh
" }
" Bundles {
    " Setup Bundle Support {{{
        filetype off
        call plug#begin()
    " }}}

    " Deps {
        "Plug 'gmarik/vundle'
        Plug 'MarcWeber/vim-addon-mw-utils'
        Plug 'tomtom/tlib_vim'
        Plug 'mileszs/ack.vim'
        if executable('ag')
            let g:ackprg = 'ag --nogroup --smart-case'
        endif
    " }
    
    " Good-Text-Editor {{{
        Plug 'tpope/vim-repeat'
        "Plug 'gcmt/taboo.vim'

        Plug 'nelstrom/vim-visual-star-search'  " *来搜索v选中的文本
        Plug 'haya14busa/incsearch.vim'
        Plug 'kristijanhusak/vim-multiple-cursors' " ctrl-n
        Plug 'tpope/vim-abolish' " 牛逼的replace
        Plug 'Lokaltog/vim-easymotion' " <leader><leader>s

        Plug 'tommcdo/vim-exchange' " cx to exchange
        Plug 'tpope/vim-surround'
        Plug 'jiangmiao/auto-pairs'
        Plug 'matze/vim-move'  " Ctrl+j/k 移动当前行
            let g:move_key_modifier = 'C'
        Plug 'sjl/gundo.vim'
        Plug 'w0rp/ale'
            let g:ale_linters = {'javascript': [ 'eslint']}
            let g:ale_fixers = {'javascript': ['eslint']}

        Plug 'kana/vim-textobj-user'
        Plug 'kana/vim-textobj-indent'
        Plug 'kana/vim-textobj-entire'
        Plug 'reedes/vim-textobj-quote'
        Plug 'reedes/vim-textobj-sentence'
        Plug 'kana/vim-textobj-function'
        Plug 'thinca/vim-textobj-function-javascript'

        Plug 'christoomey/vim-tmux-navigator'
            function! s:goyo_enter()
                Plug 'junegunn/goyo.vim'
              if exists('$TMUX')
                silent !tmux set status off
              endif
            endfunction

            function! s:goyo_leave()
              if exists('$TMUX')
                silent !tmux set status on
              endif
            endfunction

            autocmd! User GoyoEnter nested call <SID>goyo_enter()
            autocmd! User GoyoLeave nested call <SID>goyo_leave()
        Plug 'junegunn/limelight.vim'
            let g:limelight_default_coefficient = 0.7
            let g:limelight_conceal_ctermfg = 'gray'
    " }}}

    " Good-IDE-Core {{{
        Plug 'editorconfig/editorconfig-vim'
        Plug 'tpope/vim-vinegar'
        Plug 'scrooloose/nerdtree'
        "Plug 'jistr/vim-nerdtree-tabs'
        Plug 'Xuyuanp/nerdtree-git-plugin'
        Plug 'ctrlpvim/ctrlp.vim'
        Plug 'tacahiroy/ctrlp-funky'
        Plug 'dyng/ctrlsf.vim'
        Plug '/usr/local/opt/fzf'
        Plug 'junegunn/fzf.vim'

        Plug 'bling/vim-airline' " 状态条
        "Plug 'nathanaelkane/vim-indent-guides' "代码缩进加竖线~~
        Plug 'Yggdroot/indentLine'
        Plug 'mhinz/vim-signify' "Show a diff via Vim sign column

        Plug 'terryma/vim-expand-region'

        Plug 'cohama/agit.vim'
        Plug 'tpope/vim-fugitive'
        "Plug 'gregsexton/gitv'
        Plug 'scrooloose/nerdcommenter'
        "Plug 'tpope/vim-commentary' "和nerdcommenter对比一下
        Plug 'godlygeek/tabular'
        "Plug 'junegunn/vim-easy-align' "这个和tabular哪个好有时间研究一下
        "Plug 'floobits/floobits-neovim' "协同
        Plug 'kristijanhusak/vim-carbon-now-sh'
        Plug 'janko-m/vim-test'
        let g:test#strategy="neovim"
        Plug 'skywind3000/asyncrun.vim'
    " }}}

    " Color {{{
        "Plug 'dracula/vim', { 'as': 'dracula' }
        Plug 'vim-airline/vim-airline-themes'
        let g:airline_theme='ayu_mirage'
        Plug 'ayu-theme/ayu-vim'
        let g:ayucolor="mirage"
        "let g:ayucolor="dark"
        "let g:ayucolor="light"
        function! s:SwitchAyuStyle()
          if g:ayucolor == "mirage"
            let g:ayucolor = "light"
            "let g:airline_theme='ayu'
          else
            let g:ayucolor = "mirage"
            let g:airline_theme='ayu_mirage'
          endif
          colorscheme ayu
        endfunction
        map <silent> <F6> :call <SID>SwitchAyuStyle()<CR>
        let g:indentLine_char = ''
        let g:indentLine_first_char = ''
        let g:indentLine_showFirstIndentLevel = 1
        let g:indentLine_setColors = 0
        "Plug 'morhetz/gruvbox'
        "Plug 'altercation/vim-colors-solarized'
        "Plug 'spf13/vim-colors'
        "Plug 'edkolev/tmuxline.vim'
    " }}}

    " otherLanguage {{{
        Plug 'plasticboy/vim-markdown'
        Plug 'jceb/vim-orgmode'
        Plug 'dag/vim-fish'
    " }}}

    " Snippets & AutoComplete {{{
        "Plug 'honza/vim-snippets'
        Plug 'imshenshen/vim-snippets'
        "Plug 'Valloric/YouCompleteMe',{ 'do': './install.py --tern-completer'}
        Plug 'autozimu/LanguageClient-neovim', {
              \ 'branch': 'next',
              \ 'do': 'bash install.sh',
              \ 'for':['javascript' ,'vue'],
              \ }

        set hidden

        let g:LanguageClient_serverCommands = {
              \ 'javascript': ['javascript-typescript-stdio'],
              \ 'javascript.jsx': ['javascript-typescript-stdio'],
              \ 'go': ['go-langserver'],
              \ }

        let g:LanguageClient_trace= "verbose"
        nnoremap <silent> K :call LanguageClient_textDocument_hover()<CR>
        nnoremap <silent> gd :call LanguageClient_textDocument_definition()<CR>
        nnoremap <silent> <F2> :call LanguageClient_textDocument_rename()<CR>
        if has('nvim')
            Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
        else
            Plug 'Shougo/deoplete.nvim'
            Plug 'roxma/nvim-yarp'
            Plug 'roxma/vim-hug-neovim-rpc'
        endif
        let g:deoplete#enable_at_startup = 1
        Plug 'SirVer/ultisnips'
        Plug 'ervandew/supertab'
    " }}}

    " Javascript {{{
        Plug 'elzr/vim-json',{'for':['javascript','json']}
        Plug 'pangloss/vim-javascript',{'for':['vue', 'javascript' ]}
        let g:javascript_plugin_jsdoc = 1
        "Plug 'briancollins/vim-jst',{'for':'javascript'}
        Plug 'kchmck/vim-coffee-script' , {'for':'coffeescript'}
        "Plug 'othree/yajs.vim',{'for':'javascript'}
        Plug 'posva/vim-vue' ,{'for':'vue'}
        Plug 'heavenshell/vim-jsdoc', {'for':[ 'javascript' , 'vue']}
    " }}}

      " HTML&CSS {{{
        Plug 'hail2u/vim-css3-syntax'
        Plug 'gorodinskiy/vim-coloresque'
        Plug 'tpope/vim-haml'
        Plug 'digitaltoad/vim-pug'
        Plug 'mattn/emmet-vim' ,{'for':['css','html']}

        Plug 'groenewege/vim-less'
        Plug 'ryanoasis/vim-devicons'
    " }}}
    call plug#end()
" }


" General {

    filetype plugin indent on   " Automatically detect file types.
    syntax on                   " Syntax highlighting
    let &t_8f="\<Esc>[38;2;%lu;%lu;%lum"
    let &t_8b="\<Esc>[48;2;%lu;%lu;%lum"
    set termguicolors
    set mousehide               " Hide the mouse cursor while typing
    scriptencoding utf-8
    "set relativenumber
    set incsearch

    autocmd FileType javascript set formatprg='prettier-standard\ --stdin'
    autocmd FileType vue syntax sync fromstart
    "tnoremap <Esc> <C-\><C-n>

    "set autowrite                       " Automatically write a file when leaving a modified buffer
    set shortmess+=filmnrxoOtT          " Abbrev. of messages (avoids 'hit enter')
    set viewoptions=folds,options,cursor,unix,slash " Better Unix / Windows compatibility
    set virtualedit=onemore             " Allow for cursor beyond last character
    "set spell                           " Spell checking on
    set hidden                          " Allow buffer switching without saving
    set iskeyword-=.                    " '.' is an end of word designator
    set iskeyword-=#                    " '#' is an end of word designator
    set iskeyword-=-                    " '-' is an end of word designator

    " http://vim.wikia.com/wiki/Restore_cursor_to_file_position_in_previous_editing_session
    " Restore cursor to file position in previous editing session
    " To disable this, add the following to your .vimrc.before.local file:
    "   let g:spf13_no_restore_cursor = 1
    function! ResCur()
        if line("'\"") <= line("$")
            normal! g`"
            return 1
        endif
    endfunction

    augroup resCur
        autocmd!
        autocmd BufWinEnter * call ResCur()
    augroup END

    " Setting up the directories {
    set backup                  " Backups are nice ...
    if has('persistent_undo')
      set undofile                " So is persistent undo ...
      set undolevels=1000         " Maximum number of changes that can be undone
      set undoreload=10000        " Maximum number lines to save for undo on a buffer reload
    endif

    " Add exclusions to mkview and loadview
    " eg: *.*, svn-commit.tmp
    let g:skipview_files = [
          \ '\[example pattern\]'
          \ ]
    " }
" }

" Vim UI {

    let g:rehash256 =1
    set noshowmode     "有了airline/powerline就不用在下面显示当前模式了
    set showtabline=2
    "set t_Co=256
    "colorscheme gruvbox
    "color dracula
    "set bg=dark         " Assume a dark background
    colorscheme ayu
    set mouse=a

    "set cursorline                  " Highlight current line

    highlight clear SignColumn      " SignColumn should match background
    highlight clear LineNr          " Current line number row will have same background color in relative mode
    "highlight clear CursorLineNr    " Remove highlight color from current line number

    if has('cmdline_info')
        set ruler                   " Show the ruler
        set rulerformat=%30(%=\:b%n%y%m%r%w\ %l,%c%V\ %P%) " A ruler on steroids
        set showcmd                 " Show partial commands in status line and
                                    " Selected characters/lines in visual mode
    endif

    if !exists('g:airline_symbols')
        let g:airline_symbols = {}
    endif
    if exists('$TMUX')
        let &t_SI = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=1\x7\<Esc>\\"
        let &t_SR = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=2\x7\<Esc>\\"
        let &t_EI = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=0\x7\<Esc>\\"
    else
        let &t_SI = "\<Esc>]50;CursorShape=1\x7"
        let &t_SR = "\<Esc>]50;CursorShape=2\x7"
        let &t_EI = "\<Esc>]50;CursorShape=0\x7"
    endif

    let g:airline_symbols.space = "\ua0"
    let g:airline_symbols.branch = ''
    let g:airline_symbols.readonly = ''
    let g:airline_symbols.linenr = ''
    "let g:airline_left_sep = ''
    "let g:airline_left_alt_sep = ''
    "let g:airline_right_sep = ''
    "let g:airline_right_alt_sep = ''
    "let g:airline_section_z='%p'
    let g:airline_left_sep = ""
    let g:airline_left_alt_sep = ""
    let g:airline_right_sep = ""
    let g:airline_right_alt_sep = ""
    let g:airline_section_z='%p'

    let g:airline#extensions#ctrlp#color_template = "visual"
    let g:airline#extensions#ctrlp#show_adjacent_modes = 0
    let g:airline#extensions#ale#enabled = 1

    "let g:ctrlsf_position = 'bottom'
    "let g:ctrlsf_regex_pattern=1

    set linespace=0                 " No extra spaces between rows
    set number                      " Line numbers on
    set showmatch                   " Show matching brackets/parenthesis
    set winminheight=0              " Windows can be 0 line high
    set ignorecase                  " Case insensitive search
    set smartcase                   " Case sensitive when uc present
    set wildmode=list:longest,full  " Command <Tab> completion, list matches, then longest common part, then all.
    set whichwrap=b,s,h,l,<,>,[,]   " Backspace and cursor keys wrap too
    set scrolljump=5                " Lines to scroll when cursor leaves screen
    set scrolloff=3                 " Minimum lines to keep above and below cursor
    set foldenable                  " Auto fold code
    set foldmethod=marker
    set foldnestmax=10
    set foldlevelstart=10
    set list
    set colorcolumn+=1


    function! MyTabLine()
      let s = '' " complete tabline goes here
      " loop through each tab page
      for t in range(tabpagenr('$'))
        " set highlight
        if t + 1 == tabpagenr()
          let s .= '%#TabLineSel#'
        else
          let s .= '%#TabLine#'
        endif
        " set the tab page number (for mouse clicks)
        let s .= '%#TabNum#'
        let s .= '%' . (t + 1) . 'T'
        let s .= ' '
        " set page number string
        let s .= t + 1 . ' '
        " get buffer names and statuses
        let n = ''      "temp string for buffer names while we loop and check buftype
        let m = 0       " &modified counter
        let bc = len(tabpagebuflist(t + 1))     "counter to avoid last ' '
        " loop through each buffer in a tab
        for b in tabpagebuflist(t + 1)
          " buffer types: quickfix gets a [Q], help gets [H]{base fname}
          " others get 1dir/2dir/3dir/fname shortened to 1/2/3/fname
          if getbufvar( b, "&buftype" ) == 'help'
            let n .= '[H]' . fnamemodify( bufname(b), ':t:s/.txt$//' )
          elseif getbufvar( b, "&buftype" ) == 'quickfix'
            let n .= '[Q]'
          else
            let n .= pathshorten(bufname(b))
          endif
          " check and ++ tab's &modified count
          if getbufvar( b, "&modified" )
            let m += 1
          endif
          " no final ' ' added...formatting looks better done later
          if bc > 1
            let n .= ' '
          endif
          let bc -= 1
        endfor
        " add modified label [n+] where n pages in tab are modified
        if m > 0
          let s .= '[' . m . '+]'
        endif
        " select the highlighting for the buffer names
        " my default highlighting only underlines the active tab
        " buffer names.
        if t + 1 == tabpagenr()
          let s .= '%#TabLineSel#'
        else
          let s .= '%#TabLine#'
        endif
        " add buffer names
        if n == ''
          let s.= '[New]'
        else
          let s .= n
        endif
        " switch to no underlining and add final space to buffer list
        let s .= ' '
      endfor
      " after the last tab fill with TabLineFill and reset tab page nr
      let s .= '%#TabLineFill#%T'
      " right-align the label to close the current tab page
      if tabpagenr('$') > 1
        let s .= '%=%#TabLineFill#%999Xclose'
      endif
      return s
    endfunction
    set tabline=%!MyTabLine()  " custom tab pages line
    set showtabline=2
    highlight link TabNum Special


    "if exists("+showtabline")
      "function! MyTabLine()
        "let s = ''
        "let wn = ''
        "let t = tabpagenr()
        "let i = 1
        "while i <= tabpagenr('$')
          "let buflist = tabpagebuflist(i)
          "let winnr = tabpagewinnr(i)
          "let s .= '%' . i . 'T'
          "let s .= (i == t ? '%1*' : '%2*')
          "let s .= ' '
          "let wn = tabpagewinnr(i,'$')

          "let s .= '%#TabNum#'
          "let s .= i
          "" let s .= '%*'
          "let s .= (i == t ? '%#TabLineSel#' : '%#TabLine#')
          "let bufnr = buflist[winnr - 1]
          "let file = bufname(bufnr)
          "let buftype = getbufvar(bufnr, 'buftype')
          "if buftype == 'nofile'
            "if file =~ '\/.'
              "let file = substitute(file, '.*\/\ze.', '', '')
            "endif
          "else
            "let file = fnamemodify(file, ':p:t')
          "endif
          "if file == ''
            "let file = '[No Name]'
          "endif
          "let s .= ' ' . file . ' '
          "let i = i + 1
        "endwhile
        "let s .= '%T%#TabLineFill#%='
        "let s .= (tabpagenr('$') > 1 ? '%999XX' : 'X')
        "return s
      "endfunction
      "set stal=2
      "set showtabline=2
      "set tabline=%!MyTabLine()
      "highlight link TabNum Special
    "endif
" }

" Formatting {

    set nowrap                      " Do not wrap long lines
    set shiftwidth=2                " Use indents of 4 spaces
    set expandtab                   " Tabs are spaces, not tabs
    set tabstop=2                   " An indentation every four columns
    set softtabstop=2               " Let backspace delete indent
    set nojoinspaces                " Prevents inserting two spaces after punctuation on a join (J)
    set splitright                  " Puts new vsplit windows to the right of the current
    set splitbelow                  " Puts new split windows to the bottom of the current
    "set matchpairs+=<:>             " Match, to be used with %
    set pastetoggle=<F12>           " pastetoggle (sane indentation on pastes)
    "set comments=sl:/*,mb:*,elx:*/  " auto format comment blocks
    " Remove trailing whitespaces and ^M chars
    " To disable the stripping of whitespace, add the following to your
    " .vimrc.before.local file:
    "   let g:spf13_keep_trailing_whitespace = 1
    "autocmd FileType c,cpp,java,go,php,javascript,puppet,python,rust,twig,xml,yml,perl,sql autocmd BufWritePre <buffer> if !exists('g:spf13_keep_trailing_whitespace') | call StripTrailingWhitespace() | endif
    autocmd BufNewFile,BufRead *.html.twig set filetype=html.twig
    autocmd BufNewFile,BufRead *.coffee set filetype=coffee
    "autocmd BufNewFile,BufRead *.jade set filetype=pug

    autocmd FileType yaml,pug,jade set foldmethod=indent
" }

" Key (re)Mappings {

    let mapleader = "\<Space>"
    let maplocalleader = ','

    let g:tmux_navigator_no_mappings = 1
    nnoremap  <M-h> :TmuxNavigateLeft<CR>
    nnoremap  <M-j> :TmuxNavigateDown<CR>
    nnoremap  <M-k> :TmuxNavigateUp<CR>
    nnoremap  <M-l> :TmuxNavigateRight<CR>
    "nnoremap <silent> {Previous-Mapping} :TmuxNavigatePrevious<cr>

    map <S-H> gT
    map <S-L> gt
    " Stupid shift key fixes
    if !exists('g:spf13_no_keyfixes')
        if has("user_commands")
            command! -bang -nargs=* -complete=file E e<bang> <args>
            command! -bang -nargs=* -complete=file W w<bang> <args>
            command! -bang -nargs=* -complete=file Wq wq<bang> <args>
            command! -bang -nargs=* -complete=file WQ wq<bang> <args>
            command! -bang Wa wa<bang>
            command! -bang WA wa<bang>
            command! -bang Q q<bang>
            command! -bang QA qa<bang>
            command! -bang Qa qa<bang>
        endif

        cmap Tabe tabe
    endif

    "查找后，一直高亮是不好的，这里给清屏功能添加了【暂时关闭查找】的功能，之后还可以继续使用N来查找上次的搜索词
    nnoremap <silent> <C-l> :<C-u>nohlsearch<CR><C-l>

    " Yank from the cursor to the end of the line, to be consistent with C and D.
    nnoremap Y y$

    " Find merge conflict markers
    map <leader>fc /\v^[<\|=>]{7}( .*\|$)<CR>

    " Shortcuts
    " Change Working Directory to that of the current file
    cmap cd. lcd %:p:h

    "缩进之后继续选择，也就是说可连续缩进
    vnoremap < <gv
    vnoremap > >gv

    " Allow using the repeat operator with a visual selection (!)
    " http://stackoverflow.com/a/8064607/127816
    vnoremap . :normal .<CR>

    " For when you forget to sudo.. Really Write the file.
    cmap w!! w !sudo tee % >/dev/null

    " Easier formatting
    nnoremap <silent> <leader>q gwip

    nnoremap <Leader>w :w<CR>
    vmap <Leader>y "+y
    vmap <Leader>d "+d
    nmap <Leader>p "+p
    nmap <Leader>P "+P
    noremap <leader>p :set paste<CR>:put *<CR>:set nopaste<CR>
    vmap <Leader>P "+P
    " 默认的ci(会作用在外层，修正一下
    function New_cib()
        if search("(","bn") == line(".")
            sil exe "normal! f)ci("
            sil exe "normal! l"
            startinsert
        else
            sil exe "normal! f(ci("
            sil exe "normal! l"
            startinsert
        endif
    endfunction

    nnoremap ci( :call New_cib()<CR>
    nnoremap cib :call New_cib()<CR>
" }

" Plugins {

    "expand-region {
    vmap v <Plug>(expand_region_expand)
    vmap <S-v> <Plug>(expand_region_shrink)
    call expand_region#custom_text_objects({
        \ 'ic'  :0,
        \ 'i.'  :0,
        \ 'a"'  :0,
        \ 'a''' :0,
        \ 'a]'  :1,
        \ 'ab'  :1,
        \ 'aB'  :1,
        \ 'ii'  :1,
        \ 'ai'  :1,
        \ 'if'  :1,
        \ 'af'  :1,
        \ 'iF'  :1,
        \ 'aF'  :1,
        \ })
    "}
    " fugitive
    nmap <Leader>k :Gcommit<CR>
    imap <expr> <tab> emmet#expandAbbrIntelligent("\<tab>")

    " Unite {
    "
    if !exists('g:unite_source_menu_menus')
        let g:unite_source_menu_menus = {}
    endif
    let g:unite_source_menu_menus.git = {
        \ 'description' : '            gestionar repositorios git
        \                            ⌘ [espacio]g',
    \}
    let g:unite_source_menu_menus.git.command_candidates = [
         \['▷ git status       (Fugitive)                                ⌘ ,gs',
            \'Gstatus']
    \]

    let g:unite_source_grep_command = 'ag'
        let g:unite_source_grep_default_opts = '--ignore ''node_modules''  '
    " }


    " TextObj User {
        if exists('g:loaded_textobj_camelcase')
          finish
        endif

        call textobj#user#plugin('camelcase', {
        \      '-': {
        \           '*pattern*': '[A-Za-z][a-z0-9]\+',
        \           'select': ['ac', 'ic'],
        \      },
        \   })

        let loaded_textobj_camelcase = 1

        if exists('g:loaded_textobj_dotseparated')
          finish
        endif


        call textobj#user#plugin('dotsep', {
        \   '-': {
        \     'select-a-function': 'FindDotA',
        \     'select-a': 'a.',
        \     'select-i-function': 'FindDotI',
        \     'select-i': 'i.',
        \   },
        \ })


        function! FindDotA()
            call search('\v(\.|\s|^)', 'eb', line('.'))
            let head_pos = getpos('.')
            call search('\v(\.|\s|$)', 'e', line('.'))
            let tail_pos = getpos('.')
            return ['v', head_pos, tail_pos]
        endfunction


        function! FindDotI()
            call search('\v(\.|\s|^)', 'eb', line('.'))
            " If not at the beginning of a line, move right.
            let char_under_cursor = getline('.')[col('.')-1]
            let in_first_col = col('.') == 1
            if !in_first_col || char_under_cursor =~ '\v(\.|\s)'
                normal! l
            endif
            let head_pos = getpos('.')
            call search('\v(\.|\s|$)', 'e', line('.'))
            " If not at the end of a line, move left.
            let char_under_cursor = getline('.')[col('.')-1]
            let in_last_col = col('.') == col('$') - 1
            if !in_last_col || char_under_cursor =~ '\v(\.|\s)'
                normal! h
            endif
            let tail_pos = getpos('.')
            return ['v', head_pos, tail_pos]
        endfunction


        let g:loaded_textobj_dotseparated = 1
    " }

    " TextObj Sentence {
        augroup textobj_sentence
          autocmd!
          autocmd FileType markdown call textobj#sentence#init()
          autocmd FileType textile call textobj#sentence#init()
          autocmd FileType text call textobj#sentence#init()
        augroup END
    " }

    " TextObj Quote {
        augroup textobj_quote
            autocmd!
            autocmd FileType markdown call textobj#quote#init()
            autocmd FileType textile call textobj#quote#init()
            autocmd FileType text call textobj#quote#init({'educate': 0})
        augroup END
    " }



    " Ctags {
        set tags=./tags;/,~/.vimtags

        " Make tags placed in .git/tags file available in all levels of a repository
        let gitroot = substitute(system('git rev-parse --show-toplevel'), '[\n\r]', '', 'g')
        if gitroot != ''
            let &tags = &tags . ',' . gitroot . '/.git/tags'
        endif
    " }


    " NerdTree {
        "nmap <F1> <plug>NERDTreeToggle<CR>
        nmap <F1> :NERDTreeToggle<CR>
        nmap <leader>nt :NERDTreeFind<CR>
        let NERDTreeMinimalUI=1
        let NERDTreeDirArrows=1
        let NERDTreeShowBookmarks=1
        let NERDTreeIgnore=['\.py[cd]$', '\~$', '\.swo$', '\.swp$', '^\.git$', '^\.hg$', '^\.svn$', '\.bzr$','.DS_Store','.idea']
        let NERDTreeChDirMode=0
        let NERDTreeQuitOnOpen=0
        let NERDTreeMouseMode=2
        let NERDTreeShowHidden=1
        let g:nerdtree_tabs_open_on_gui_startup=0
    " }

    " Tabularize {
        nmap <Leader>a& :Tabularize /&<CR>
        vmap <Leader>a& :Tabularize /&<CR>
        nmap <Leader>a= :Tabularize /^[^=]*\zs=<CR>
        vmap <Leader>a= :Tabularize /^[^=]*\zs=<CR>
        nmap <Leader>a=> :Tabularize /=><CR>
        vmap <Leader>a=> :Tabularize /=><CR>
        nmap <Leader>a: :Tabularize /:<CR>
        vmap <Leader>a: :Tabularize /:<CR>
        nmap <Leader>a:: :Tabularize /:\zs<CR>
        vmap <Leader>a:: :Tabularize /:\zs<CR>
        nmap <Leader>a, :Tabularize /,<CR>
        vmap <Leader>a, :Tabularize /,<CR>
        nmap <Leader>a,, :Tabularize /,\zs<CR>
        vmap <Leader>a,, :Tabularize /,\zs<CR>
        nmap <Leader>a<Bar> :Tabularize /<Bar><CR>
        vmap <Leader>a<Bar> :Tabularize /<Bar><CR>
        " 输入|时候自动format
        inoremap <silent> <Bar>   <Bar><Esc>:call <SID>align()<CR>a
        function! s:align()
          let p = '^\s*|\s.*\s|\s*$'
          if exists(':Tabularize') && getline('.') =~# '^\s*|' && (getline(line('.')-1) =~# p || getline(line('.')+1) =~# p)
            let column = strlen(substitute(getline('.')[0:col('.')],'[^|]','','g'))
            let position = strlen(matchstr(getline('.')[0:col('.')],'.*|\s*\zs.*'))
            Tabularize/|/l1
            normal! 0
            call search(repeat('[^|]*|',column).'\s\{-\}'.repeat('.',position),'ce',line('.'))
          endif
        endfunction
    " }

    " JSON {
        nmap <leader>jt <Esc>:%!python -m json.tool<CR><Esc>:set filetype=json<CR>
        let g:vim_json_syntax_conceal = 0
    " }

    " ctrlp {
        let g:ctrlp_working_path_mode = 'ra'
        nnoremap <silent> <D-t> :CtrlP<CR>
        nnoremap <silent> <D-r> :CtrlPMRU<CR>
        let g:ctrlp_custom_ignore = {
            \ 'dir':  '\.git$\|\.hg$\|\.svn$',
            \ 'file': '\.exe$\|\.so$\|\.dll$\|\.pyc$' }

        if executable('ag')
            let s:ctrlp_fallback = 'ag %s --nocolor -l -g ""'
        elseif executable('ack-grep')
            let s:ctrlp_fallback = 'ack-grep %s --nocolor -f'
        elseif executable('ack')
            let s:ctrlp_fallback = 'ack %s --nocolor -f'
        " On Windows use "dir" as fallback command.
        elseif WINDOWS()
            let s:ctrlp_fallback = 'dir %s /-n /b /s /a-d'
        else
            let s:ctrlp_fallback = 'find %s -type f'
        endif
        if exists("g:ctrlp_user_command")
            unlet g:ctrlp_user_command
        endif
        let g:ctrlp_user_command = {
            \ 'types': {
                \ 1: ['.git', 'cd %s && git ls-files . --cached --exclude-standard --others'],
                \ 2: ['.hg', 'hg --cwd %s locate -I .'],
            \ },
            \ 'fallback': s:ctrlp_fallback
        \ }

        " CtrlP extensions
        let g:ctrlp_extensions = ['funky']

        "funky
        nnoremap <Leader>fu :CtrlPFunky<Cr>
    "}

    " TagBar {
        if isdirectory(expand("~/.vim/bundle/tagbar/"))
            nnoremap <silent> <leader>tt :TagbarToggle<CR>
        endif
    "}


    " Gundo {
            nnoremap <Leader>u :GundoToggle<CR>
    " }

    " indent_guides {
        if isdirectory(expand("~/.vim/bundle/vim-indent-guides/"))
            let g:indent_guides_start_level = 2
            let g:indent_guides_guide_size = 1
            let g:indent_guides_enable_on_vim_startup = 1
        endif
    " }

    "  Youcompleteme with ultisnips and supertab
    let g:UltiSnipsExpandTrigger          =     "<tab>"
    let g:UltiSnipsListSnippets            =  "<c-l>"
    let g:UltiSnipsJumpForwardTrigger       = "<tab>"
    let g:UltiSnipsJumpBackwardTrigger       ="<s-tab>"
    let g:ycm_key_list_select_completion = ['<C-n>','<DOWN>']
    let g:ycm_key_list_previous_completion = ['<C-p>','<UP>']
    let g:SuperTabDefaultCompletionType = '<C-n>'
    "  }

" }


" Functions {

    " Initialize directories {
    function! InitializeDirectories()
        let parent = $HOME
        let prefix = 'vim'
        let dir_list = {
                    \ 'backup': 'backupdir',
                    \ 'views': 'viewdir',
                    \ 'swap': 'directory' }

        if has('persistent_undo')
            let dir_list['undo'] = 'undodir'
        endif

        " To specify a different directory in which to place the vimbackup,
        " vimviews, vimundo, and vimswap files/directories, add the following to
        let common_dir = parent . '/.' . prefix
        for [dirname, settingname] in items(dir_list)
            let directory = common_dir . dirname . '/'
            if exists("*mkdir")
                if !isdirectory(directory)
                    call mkdir(directory)
                endif
            endif
            if !isdirectory(directory)
                echo "Warning: Unable to create backup directory: " . directory
                echo "Try: mkdir -p " . directory
            else
                let directory = substitute(directory, " ", "\\\\ ", "g")
                exec "set " . settingname . "=" . directory
            endif
        endfor
    endfunction
    call InitializeDirectories()
    """}
" }
"hi Normal guibg=NONE ctermbg=NONE
