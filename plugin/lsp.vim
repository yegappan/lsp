" LSP plugin for vim9

" Needs Vim 8.2.2342 and higher
if v:version < 802 || !has('patch-8.2.2342')
  finish
endif

" Perform completion in insert mode automatically. Otherwise use
" omni-complete.
if !exists('g:LSP_24x7_Complete')
  let g:LSP_24x7_Complete = v:true
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
command! -nargs=0 -bar LspDiagShow call lsp#showDiagnostics()
command! -nargs=0 -bar LspDiagCurrent call lsp#showCurrentDiag()
command! -nargs=0 -bar LspDiagFirst call lsp#jumpToDiag('first')
command! -nargs=0 -bar LspDiagNext call lsp#jumpToDiag('next')
command! -nargs=0 -bar LspDiagPrev call lsp#jumpToDiag('prev')
command! -nargs=0 -bar LspShowReferences call lsp#showReferences()
command! -nargs=0 -bar LspHighlight call lsp#docHighlight()
command! -nargs=0 -bar LspHighlightClear call lsp#docHighlightClear()
command! -nargs=0 -bar LspOutline call lsp#outline()
command! -nargs=0 -bar -range=% LspFormat call lsp#textDocFormat(<range>, <line1>, <line2>)
command! -nargs=0 -bar LspCalledBy call lsp#incomingCalls()
command! -nargs=0 -bar LspCalling call lsp#outgoingCalls()
command! -nargs=0 -bar LspRename call lsp#rename()
command! -nargs=0 -bar LspCodeAction call lsp#codeAction()
command! -nargs=? -bar LspSymbolSearch call lsp#symbolSearch(<q-args>)
command! -nargs=0 -bar LspHover call lsp#hover()
command! -nargs=0 -bar LspSelectionRange call lsp#selectionRange()
command! -nargs=0 -bar LspFold call lsp#foldDocument()
command! -nargs=0 -bar LspWorkspaceListFolders call lsp#listWorkspaceFolders()
command! -nargs=1 -bar -complete=dir LspWorkspaceAddFolder call lsp#addWorkspaceFolder(<q-args>)
command! -nargs=1 -bar -complete=dir LspWorkspaceRemoveFolder call lsp#removeWorkspaceFolder(<q-args>)

" vim: shiftwidth=2 softtabstop=2
