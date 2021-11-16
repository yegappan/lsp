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

if !exists('g:LSP_Show_Signature')
  let g:LSP_Show_Signature = v:true
endif

if !exists('g:LSP_Hover_In_Preview')
  let g:LSP_Hover_In_Preview = v:false
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

" Add the GUI menu entries
if has('gui_running')
  anoremenu <silent> L&sp.Goto.Definition :call lsp#gotoDefinition()<CR>
  anoremenu <silent> L&sp.Goto.Declaration :call lsp#gotoDeclaration()<CR>
  anoremenu <silent> L&sp.Goto.Implementation :call lsp#gotoImplementation()<CR>
  anoremenu <silent> L&sp.Goto.TypeDef :call lsp#gotoTypedef()<CR>

  anoremenu <silent> L&sp.Show\ Signature :call lsp#showSignature()<CR>
  anoremenu <silent> L&sp.Show\ References :call lsp#showReferences()<CR>
  anoremenu <silent> L&sp.Show\ Detail :call lsp#hover()<CR>
  anoremenu <silent> L&sp.Outline :call lsp#outline()<CR>

  anoremenu <silent> L&sp.Symbol\ Search :call lsp#symbolSearch('')<CR>
  anoremenu <silent> L&sp.CalledBy :call lsp#incomingCalls()<CR>
  anoremenu <silent> L&sp.Calling :call lsp#outgoingCalls()<CR>
  anoremenu <silent> L&sp.Rename :call lsp#rename()<CR>
  anoremenu <silent> L&sp.Code\ Action :call lsp#codeAction()<CR>

  anoremenu <silent> L&sp.Highlight\ Symbol :call lsp#docHighlight()<CR>
  anoremenu <silent> L&sp.Highlight\ Clear :call lsp#docHighlightClear()<CR>

  " Diagnostics
  anoremenu <silent> L&sp.Diagnostics.Current :call lsp#showCurrentDiag<CR>
  anoremenu <silent> L&sp.Diagnostics.Show\ All :call lsp#showDiagnostics()<CR>
  anoremenu <silent> L&sp.Diagnostics.First :call lsp#jumpToDiag('first')<CR>
  anoremenu <silent> L&sp.Diagnostics.Next :call lsp#jumpToDiag('next')<CR>
  anoremenu <silent> L&sp.Diagnostics.Prev :call lsp#jumpToDiag('prev')<CR>

  if &mousemodel =~ 'popup'
    anoremenu <silent> PopUp.L&sp.Go\ to\ Definition
	  \ :call lsp#gotoDefinition()<CR>
    anoremenu <silent> PopUp.L&sp.Go\ to\ Declaration
	  \ :call lsp#gotoDeclaration()<CR>
    anoremenu <silent> Popup.L&sp.Find\ All\ References
	  \ :call lsp#showReferences()<CR>
    anoremenu <silent> PopUp.L&sp.Show\ Detail
          \ :call lsp#hover()<CR>
    anoremenu <silent> PopUp.L&sp.Highlight\ Symbol
          \ :call lsp#docHighlight()<CR>
    anoremenu <silent> PopUp.L&sp.Highlight\ Clear
          \ :call lsp#docHighlightClear()<CR>
  endif
endif

" vim: shiftwidth=2 softtabstop=2
