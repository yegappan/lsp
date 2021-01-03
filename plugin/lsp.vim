" LSP plugin for vim9

" Needs Vim 8.2.2082 and higher
if v:version < 802 || !has('patch-8.2.2082')
  finish
endif

augroup LSPAutoCmds
  au!
  autocmd BufNewFile,BufReadPost *
			  \ call lsp#addFile(expand('<abuf>') + 0)
  autocmd BufWipeOut *
			  \ call lsp#removeFile(expand('<abuf>') + 0)
augroup END

" TODO: Is it needed to shutdown all the LSP servers when exiting Vim?
" This takes some time.
" autocmd VimLeavePre * call lsp#stopAllServers()

" LSP commands
command! -nargs=0 -bar LspShowServers call lsp#showServers()
command! -nargs=1 -bar LspSetTrace call lsp#setTraceServer(<q-args>)
command! -nargs=0 -bar LspGotoDefinition call lsp#gotoDefinition()
command! -nargs=0 -bar LspGotoDeclaration call lsp#gotoDeclaration()
command! -nargs=0 -bar LspGotoTypeDef call lsp#gotoTypedef()
command! -nargs=0 -bar LspGotoImpl call lsp#gotoImplementation()
command! -nargs=0 -bar LspShowSignature call lsp#showSignature()
command! -nargs=0 -bar LspShowDiagnostics call lsp#showDiagnostics()
command! -nargs=0 -bar LspShowReferences call lsp#showReferences()
command! -nargs=0 -bar LspHighlight call lsp#docHighlight()
command! -nargs=0 -bar LspHighlightClear call lsp#docHighlightClear()
command! -nargs=0 -bar LspShowDocSymbols call lsp#showDocSymbols()
command! -nargs=0 -bar -range=% LspFormat call lsp#textDocFormat(<range>, <line1>, <line2>)
command! -nargs=0 -bar LspCalledBy call lsp#incomingCalls()
command! -nargs=0 -bar LspCalling call lsp#outgoingCalls()
command! -nargs=0 -bar LspRename call lsp#rename()
command! -nargs=0 -bar LspCodeAction call lsp#codeAction()
command! -nargs=? -bar LspShowWorkspaceSymbols call lsp#showWorkspaceSymbols(<q-args>)
command! -nargs=0 -bar LspWorkspaceListFolders call lsp#listWorkspaceFolders()
command! -nargs=1 -bar -complete=dir LspWorkspaceAddFolder call lsp#addWorkspaceFolder(<q-args>)
command! -nargs=1 -bar -complete=dir LspWorkspaceRemoveFolder call lsp#removeWorkspaceFolder(<q-args>)
command! -nargs=0 -bar LspSelectionRange call lsp#selectionRange()
command! -nargs=0 -bar LspFold call lsp#foldDocument()
