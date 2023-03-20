if !has('vim9script') ||  v:version < 900
  " Needs Vim version 9.0 and above
  finish
endif

vim9script

# Language Server Protocol (LSP) plugin for vim

g:loaded_lsp = 1

import '../autoload/lsp/options.vim'
import autoload '../autoload/lsp/lsp.vim'


# Set LSP plugin options from 'opts'.
def g:LspOptionsSet(opts: dict<any>)
  options.OptionsSet(opts)
enddef

# Return a copy of all the LSP plugin options
def g:LspOptionsGet(): dict<any>
  return options.OptionsGet()
enddef

# Add one or more LSP servers in 'serverList'
def g:LspAddServer(serverList: list<dict<any>>)
  lsp.AddServer(serverList)
enddef

# Register 'Handler' callback function for LSP command 'cmd'.
def g:LspRegisterCmdHandler(cmd: string, Handler: func)
  lsp.RegisterCmdHandler(cmd, Handler)
enddef

# Returns true if the language server for the current buffer is initialized
# and ready to accept requests.
def g:LspServerReady(): bool
  return lsp.ServerReady()
enddef

# Returns true if the language server for 'ftype' file type is running
def g:LspServerRunning(ftype: string): bool
  return lsp.ServerRunning(ftype)
enddef

# Command line completion function for the LspSetTrace command.
def LspServerTraceComplete(arglead: string, cmdline: string, cursorpos: number): list<string>
  var l = ['off', 'messages', 'verbose']
  if arglead->empty()
    return l
  else
    return filter(l, (_, val) => val =~ arglead)
  endif
enddef

# Command line completion function for the LspSetTrace command.
def LspServerDebugComplete(arglead: string, cmdline: string, cursorpos: number): list<string>
  var l = ['off', 'on']
  if arglead->empty()
    return l
  else
    return filter(l, (_, val) => val =~ arglead)
  endif
enddef

augroup LSPAutoCmds
  au!
  autocmd BufNewFile,BufReadPost * lsp.AddFile(expand('<abuf>')->str2nr())
  # Note that when BufWipeOut is invoked, the current buffer may be different
  # from the buffer getting wiped out.
  autocmd BufWipeOut * lsp.RemoveFile(expand('<abuf>')->str2nr())
augroup END

# TODO: Is it needed to shutdown all the LSP servers when exiting Vim?
# This takes some time.
# autocmd VimLeavePre * call lsp.StopAllServers()

# LSP commands
command! -nargs=? -bar -range LspCodeAction lsp.CodeAction(<line1>, <line2>, <q-args>)
command! -nargs=0 -bar LspDiagCurrent lsp.LspShowCurrentDiag()
command! -nargs=0 -bar LspDiagFirst lsp.JumpToDiag('first')
command! -nargs=0 -bar LspDiagHighlightDisable lsp.DiagHighlightDisable()
command! -nargs=0 -bar LspDiagHighlightEnable lsp.DiagHighlightEnable()
command! -nargs=0 -bar LspDiagNext lsp.JumpToDiag('next')
command! -nargs=0 -bar LspDiagPrev lsp.JumpToDiag('prev')
command! -nargs=0 -bar LspDiagShow lsp.ShowDiagnostics()
command! -nargs=0 -bar LspDiagThis lsp.JumpToDiag('this')
command! -nargs=0 -bar LspFold lsp.FoldDocument()
command! -nargs=0 -bar -range=% LspFormat lsp.TextDocFormat(<range>, <line1>, <line2>)
command! -nargs=0 -bar LspGotoDeclaration lsp.GotoDeclaration(v:false, <q-mods>)
command! -nargs=0 -bar LspGotoDefinition lsp.GotoDefinition(v:false, <q-mods>)
command! -nargs=0 -bar LspGotoImpl lsp.GotoImplementation(v:false, <q-mods>)
command! -nargs=0 -bar LspGotoTypeDef lsp.GotoTypedef(v:false, <q-mods>)
command! -nargs=0 -bar LspHighlight call LspDocHighlight()
command! -nargs=0 -bar LspHighlightClear call LspDocHighlightClear()
command! -nargs=0 -bar LspHover lsp.Hover()
command! -nargs=0 -bar LspIncomingCalls lsp.IncomingCalls()
command! -nargs=0 -bar LspOutgoingCalls lsp.OutgoingCalls()
command! -nargs=0 -bar LspOutline lsp.Outline()
command! -nargs=0 -bar LspPeekDeclaration lsp.GotoDeclaration(v:true, <q-mods>)
command! -nargs=0 -bar LspPeekDefinition lsp.GotoDefinition(v:true, <q-mods>)
command! -nargs=0 -bar LspPeekImpl lsp.GotoImplementation(v:true, <q-mods>)
command! -nargs=0 -bar LspPeekReferences lsp.ShowReferences(v:true)
command! -nargs=0 -bar LspPeekTypeDef lsp.GotoTypedef(v:true, <q-mods>)
command! -nargs=? -bar LspRename lsp.Rename(<q-args>)
command! -nargs=0 -bar LspSelectionExpand lsp.SelectionExpand()
command! -nargs=0 -bar LspSelectionShrink lsp.SelectionShrink()
command! -nargs=1 -complete=customlist,LspServerDebugComplete -bar LspServerDebug lsp.ServerDebug(<q-args>)
command! -nargs=0 -bar LspServerRestart lsp.RestartServer()
command! -nargs=1 -complete=customlist,LspServerTraceComplete -bar LspServerTrace lsp.ServerTraceSet(<q-args>)
command! -nargs=0 -bar LspShowReferences lsp.ShowReferences(v:false)
command! -nargs=0 -bar LspShowServerCapabilities lsp.ShowServerCapabilities()
command! -nargs=0 -bar LspShowServers lsp.ShowServers()
command! -nargs=0 -bar LspShowSignature call LspShowSignature()
# Clangd specifc extension to switch from one C/C++ source file to a
# corresponding header file
command! -nargs=0 -bar LspSubTypeHierarchy lsp.TypeHierarchy(0)
command! -nargs=0 -bar LspSuperTypeHierarchy lsp.TypeHierarchy(1)
command! -nargs=0 -bar LspSwitchSourceHeader lsp.SwitchSourceHeader()
command! -nargs=? -bar LspSymbolSearch lsp.SymbolSearch(<q-args>)
command! -nargs=1 -bar -complete=dir LspWorkspaceAddFolder lsp.AddWorkspaceFolder(<q-args>)
command! -nargs=0 -bar LspWorkspaceListFolders lsp.ListWorkspaceFolders()
command! -nargs=1 -bar -complete=dir LspWorkspaceRemoveFolder lsp.RemoveWorkspaceFolder(<q-args>)

# Add the GUI menu entries
if has('gui_running')
  anoremenu <silent> L&sp.Goto.Definition :LspGotoDefinition<CR>
  anoremenu <silent> L&sp.Goto.Declaration :LspGotoDeclaration<CR>
  anoremenu <silent> L&sp.Goto.Implementation :LspGotoImpl<CR>
  anoremenu <silent> L&sp.Goto.TypeDef :LspGotoTypeDef<CR>

  anoremenu <silent> L&sp.Show\ Signature :LspShowSignature<CR>
  anoremenu <silent> L&sp.Show\ References :LspShowReferences<CR>
  anoremenu <silent> L&sp.Show\ Detail :LspHover<CR>
  anoremenu <silent> L&sp.Outline :LspOutline<CR>

  anoremenu <silent> L&sp.Symbol\ Search :LspSymbolSearch<CR>
  anoremenu <silent> L&sp.Outgoing\ Calls :LspOutgoingCalls<CR>
  anoremenu <silent> L&sp.Incoming\ Calls :LspIncomingCalls<CR>
  anoremenu <silent> L&sp.Rename :LspRename<CR>
  anoremenu <silent> L&sp.Code\ Action :LspCodeAction<CR>

  anoremenu <silent> L&sp.Highlight\ Symbol :LspHighlight<CR>
  anoremenu <silent> L&sp.Highlight\ Clear :LspHighlightClear<CR>

  # Diagnostics
  anoremenu <silent> L&sp.Diagnostics.Current :LspDiagCurrent<CR>
  anoremenu <silent> L&sp.Diagnostics.Show\ All :LspDiagShow<CR>
  anoremenu <silent> L&sp.Diagnostics.First :LspDiagFirst<CR>
  anoremenu <silent> L&sp.Diagnostics.Next :LspDiagNext<CR>
  anoremenu <silent> L&sp.Diagnostics.Prev :LspDiagPrev<CR>
  anoremenu <silent> L&sp.Diagnostics.This :LspDiagThis<CR>

  if &mousemodel =~ 'popup'
    anoremenu <silent> PopUp.L&sp.Go\ to\ Definition
	  \ :LspGotoDefinition<CR>
    anoremenu <silent> PopUp.L&sp.Go\ to\ Declaration
	  \ :LspGotoDeclaration<CR>
    anoremenu <silent> PopUp.L&sp.Find\ All\ References
	  \ :LspShowReferences<CR>
    anoremenu <silent> PopUp.L&sp.Show\ Detail
          \ :LspHover<CR>
    anoremenu <silent> PopUp.L&sp.Highlight\ Symbol
          \ :LspHighlight<CR>
    anoremenu <silent> PopUp.L&sp.Highlight\ Clear
          \ :LspHighlightClear<CR>
  endif
endif

# vim: shiftwidth=2 softtabstop=2
