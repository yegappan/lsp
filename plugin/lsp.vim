vim9script

# LSP plugin for vim9

autocmd BufRead * call lsp#add_file(expand('<afile>:p'), &filetype)
autocmd BufWipeOut * call lsp#remove_file(expand('<afile>:p'), &filetype)

# TODO: Is it needed to shutdown all the LSP servers when exiting Vim?
# This takes some time.
#autocmd VimLeavePre * call lsp#stop_all_servers()

command! -nargs=0 LspGotoDefinition call lsp#goto_definition(expand('%:p'), &filetype, line('.') - 1, col('.') - 1)
command! -nargs=0 LspGotoDeclaration call lsp#goto_declaration(expand('%:p'), &filetype, line('.') - 1, col('.') - 1)

