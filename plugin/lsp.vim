" LSP plugin for vim9

" Needs Vim 8.2.2082 and higher
if v:version < 802 || !has('patch-8.2.2082')
  finish
endif

autocmd BufReadPost * call lsp#addFile(expand('<abuf>') + 0, &filetype)
autocmd BufWipeOut * call lsp#removeFile(expand('<afile>:p'), &filetype)

" TODO: Is it needed to shutdown all the LSP servers when exiting Vim?
" This takes some time.
" autocmd VimLeavePre * call lsp#stopAllServers()

" LSP commands
command! -nargs=0 LspShowServers call lsp#showServers()
command! -nargs=0 LspGotoDefinition call lsp#gotoDefinition()
command! -nargs=0 LspGotoDeclaration call lsp#gotoDeclaration()
command! -nargs=0 LspGotoTypeDef call lsp#gotoTypedef()
command! -nargs=0 LspGotoImpl call lsp#gotoImplementation()
command! -nargs=0 LspShowSignature call lsp#showSignature()
command! -nargs=0 LspShowDiagnostics call lsp#showDiagnostics()
command! -nargs=0 LspShowReferences call lsp#showReferences()
command! -nargs=0 LspHighlight call lsp#docHighlight()
command! -nargs=0 LspHighlightClear call lsp#docHighlightClear()
command! -nargs=0 LspShowSymbols call lsp#showDocSymbols()

