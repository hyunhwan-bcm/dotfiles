" Minimal vimrc for Python with :make and clipboard sharing

" Basics
syntax on
set encoding=utf-8
set number
set expandtab
set tabstop=4
set shiftwidth=4
set softtabstop=4
set autoindent
set smartindent
set cursorline
set showmatch
set wrap
set ignorecase
set smartcase
set incsearch
set hlsearch
set laststatus=2
colorscheme default

" Share system clipboard (primary choice: + register; fallback: * register)
" Works on Linux/macOS; on WSL you may need win32yank installed.
set clipboard=unnamedplus,unnamed

" Python-specific settings
augroup python
    autocmd!
    " PEP 8 text width
    autocmd FileType python setlocal textwidth=79
    " Ensure 4-space indents
    autocmd FileType python setlocal expandtab shiftwidth=4 softtabstop=4 tabstop=4
    " Use :make to run current file with system 'python'
    autocmd FileType python setlocal makeprg=python\ %
augroup END

