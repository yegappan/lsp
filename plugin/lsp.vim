" LSP plugin for vim9

" Need Vim 8.2.2082 and higher
if v:version < 802 || !has('patch-8.2.2082')
  finish
endif

autocmd BufReadPost * call lsp#add_file(expand('<abuf>') + 0, &filetype)
autocmd BufWipeOut * call lsp#remove_file(expand('<afile>:p'), &filetype)

" TODO: Is it needed to shutdown all the LSP servers when exiting Vim?
" This takes some time.
" autocmd VimLeavePre * call lsp#stop_all_servers()

command! -nargs=0 LspShowServers call lsp#showServers()
command! -nargs=0 LspGotoDefinition call lsp#gotoDefinition(expand('%:p'), &filetype, line('.') - 1, col('.') - 1)
command! -nargs=0 LspGotoDeclaration call lsp#gotoDeclaration(expand('%:p'), &filetype, line('.') - 1, col('.') - 1)
command! -nargs=0 LspGotoTypeDef call lsp#gotoTypedef(expand('%:p'), &filetype, line('.') - 1, col('.') - 1)
command! -nargs=0 LspGotoImpl call lsp#gotoImplementation(expand('%:p'), &filetype, line('.') - 1, col('.') - 1)
command! -nargs=0 LspShowSignature call lsp#showSignature()
command! -nargs=0 LspShowDiagnostics call lsp#showDiagnostics()
command! -nargs=0 LspShowReferences call lsp#showReferences()
command! -nargs=0 LspHighlight call lsp#docHighlight()
command! -nargs=0 LspHighlightClear call lsp#docHighlightClear()
command! -nargs=0 LspShowSymbols call lsp#showDocSymbols()

