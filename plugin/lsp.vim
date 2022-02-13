vim9script

# LSP plugin for vim9

if !has('patch-8.2.2342')
  finish
endif

var opt = {}
var lspf = {}
if has('patch-8.2.4257')
  import '../autoload/lspoptions.vim' as lspoptions
  import '../autoload/lsp.vim'

  opt.LspOptionsSet = lspoptions.OptionsSet
  opt.lspOptions = lspoptions.lspOptions
  lspf.enableServerTrace = lsp.EnableServerTrace
  lspf.addServer = lsp.AddServer
  lspf.LspServerReady = lsp.ServerReady
  lspf.addFile = lsp.AddFile
  lspf.removeFile = lsp.RemoveFile
  lspf.showCurrentDiagInStatusLine = lsp.LspShowCurrentDiagInStatusLine
  lspf.showServers = lsp.ShowServers
  lspf.showServerCapabilities = lsp.ShowServerCapabilities
  lspf.setTraceServer = lsp.SetTraceServer
  lspf.gotoDefinition = lsp.GotoDefinition
  lspf.gotoDeclaration = lsp.GotoDeclaration
  lspf.gotoTypedef = lsp.GotoTypedef
  lspf.gotoImplementation = lsp.GotoImplementation
  lspf.showDiagnostics = lsp.ShowDiagnostics
  lspf.showCurrentDiag = lsp.LspShowCurrentDiag
  lspf.jumpToDiag = lsp.JumpToDiag
  lspf.diagHighlightEnable = lsp.DiagHighlightEnable
  lspf.diagHighlightDisable = lsp.DiagHighlightDisable
  lspf.showReferences = lsp.ShowReferences
  lspf.outline = lsp.Outline
  lspf.textDocFormat = lsp.TextDocFormat
  lspf.incomingCalls = lsp.IncomingCalls
  lspf.outgoingCalls = lsp.OutgoingCalls
  lspf.rename = lsp.Rename
  lspf.codeAction = lsp.CodeAction
  lspf.symbolSearch = lsp.SymbolSearch
  lspf.hover = lsp.Hover
  lspf.selectionExpand = lsp.SelectionExpand
  lspf.selectionShrink = lsp.SelectionShrink
  lspf.foldDocument = lsp.FoldDocument
  lspf.listWorkspaceFolders = lsp.ListWorkspaceFolders
  lspf.addWorkspaceFolder = lsp.AddWorkspaceFolder
  lspf.removeWorkspaceFolder = lsp.RemoveWorkspaceFolder
elseif has('patch-8.2.4019')
  import '../autoload/lspoptions.vim' as opt_import
  import '../autoload/lsp.vim' as lsp_import

  opt.LspOptionsSet = opt_import.OptionsSet
  opt.lspOptions = opt_import.lspOptions
  lspf.enableServerTrace = lsp_import.EnableServerTrace
  lspf.addServer = lsp_import.AddServer
  lspf.LspServerReady = lsp_import.ServerReady
  lspf.addFile = lsp_import.AddFile
  lspf.removeFile = lsp_import.RemoveFile
  lspf.showCurrentDiagInStatusLine = lsp_import.LspShowCurrentDiagInStatusLine
  lspf.showServers = lsp_import.ShowServers
  lspf.showServerCapabilities = lsp_import.ShowServerCapabilities
  lspf.setTraceServer = lsp_import.SetTraceServer
  lspf.gotoDefinition = lsp_import.GotoDefinition
  lspf.gotoDeclaration = lsp_import.GotoDeclaration
  lspf.gotoTypedef = lsp_import.GotoTypedef
  lspf.gotoImplementation = lsp_import.GotoImplementation
  lspf.showDiagnostics = lsp_import.ShowDiagnostics
  lspf.showCurrentDiag = lsp_import.LspShowCurrentDiag
  lspf.jumpToDiag = lsp_import.JumpToDiag
  lspf.diagHighlightEnable = lsp_import.DiagHighlightEnable
  lspf.diagHighlightDisable = lsp_import.DiagHighlightDisable
  lspf.showReferences = lsp_import.ShowReferences
  lspf.outline = lsp_import.Outline
  lspf.textDocFormat = lsp_import.TextDocFormat
  lspf.incomingCalls = lsp_import.IncomingCalls
  lspf.outgoingCalls = lsp_import.OutgoingCalls
  lspf.rename = lsp_import.Rename
  lspf.codeAction = lsp_import.CodeAction
  lspf.symbolSearch = lsp_import.SymbolSearch
  lspf.hover = lsp_import.Hover
  lspf.selectionExpand = lsp_import.SelectionExpand
  lspf.selectionShrink = lsp_import.SelectionShrink
  lspf.foldDocument = lsp_import.FoldDocument
  lspf.listWorkspaceFolders = lsp_import.ListWorkspaceFolders
  lspf.addWorkspaceFolder = lsp_import.AddWorkspaceFolder
  lspf.removeWorkspaceFolder = lsp_import.RemoveWorkspaceFolder
else
  import {lspOptions, OptionsSet} from '../autoload/lspoptions.vim'
  import {EnableServerTrace,
	  AddServer,
	  ServerReady,
	  AddFile,
	  RemoveFile,
	  LspShowCurrentDiagInStatusLine,
	  ShowServers,
	  ShowServerCapabilities,
	  SetTraceServer,
	  GotoDefinition,
	  GotoDeclaration,
	  GotoTypedef,
	  GotoImplementation,
	  ShowDiagnostics,
	  LspShowCurrentDiag,
	  JumpToDiag,
	  DiagHighlightEnable,
	  DiagHighlightDisable,
	  ShowReferences,
	  Outline,
	  TextDocFormat,
	  IncomingCalls,
	  OutgoingCalls,
	  Rename,
	  CodeAction,
	  SymbolSearch,
	  Hover,
	  SelectionExpand,
	  SelectionShrink,
	  FoldDocument,
	  ListWorkspaceFolders,
	  AddWorkspaceFolder,
	  RemoveWorkspaceFolder} from '../autoload/lsp.vim'

  opt.LspOptionsSet = OptionsSet
  opt.lspOptions = lspOptions
  lspf.enableServerTrace = EnableServerTrace
  lspf.addServer = AddServer
  lspf.LspServerReady = ServerReady
  lspf.addFile = AddFile
  lspf.removeFile = RemoveFile
  lspf.showCurrentDiagInStatusLine = LspShowCurrentDiagInStatusLine
  lspf.showServers = ShowServers
  lspf.showServerCapabilities = ShowServerCapabilities
  lspf.setTraceServer = SetTraceServer
  lspf.gotoDefinition = GotoDefinition
  lspf.gotoDeclaration = GotoDeclaration
  lspf.gotoTypedef = GotoTypedef
  lspf.gotoImplementation = GotoImplementation
  lspf.gotoDefinition = GotoDefinition
  lspf.gotoDeclaration = GotoDeclaration
  lspf.gotoTypedef = GotoTypedef
  lspf.gotoImplementation = GotoImplementation
  lspf.showDiagnostics = ShowDiagnostics
  lspf.showCurrentDiag = LspShowCurrentDiag
  lspf.jumpToDiag = JumpToDiag
  lspf.diagHighlightEnable = DiagHighlightEnable
  lspf.diagHighlightDisable = DiagHighlightDisable
  lspf.showReferences = ShowReferences
  lspf.showReferences = ShowReferences
  lspf.outline = Outline
  lspf.textDocFormat = TextDocFormat
  lspf.incomingCalls = IncomingCalls
  lspf.outgoingCalls = OutgoingCalls
  lspf.rename = Rename
  lspf.codeAction = CodeAction
  lspf.symbolSearch = SymbolSearch
  lspf.hover = Hover
  lspf.selectionExpand = SelectionExpand
  lspf.selectionShrink = SelectionShrink
  lspf.foldDocument = FoldDocument
  lspf.listWorkspaceFolders = ListWorkspaceFolders
  lspf.addWorkspaceFolder = AddWorkspaceFolder
  lspf.removeWorkspaceFolder = RemoveWorkspaceFolder
endif

def g:LspOptionsSet(opts: dict<any>)
  opt.LspOptionsSet(opts)
enddef

def g:LspServerTraceEnable()
  lspf.enableServerTrace()
enddef

def g:LspAddServer(serverList: list<dict<any>>)
  lspf.addServer(serverList)
enddef

def g:LspServerReady(): bool
  return lspf.LspServerReady()
enddef

var TshowServers = lspf.showServers
var TshowServerCapabilities = lspf.showServerCapabilities
var TsetTraceServer = lspf.setTraceServer
var TaddFile = lspf.addFile
var TremoveFile = lspf.removeFile
var TshowCurrentDiagInStatusLine = lspf.showCurrentDiagInStatusLine
var TgotoDefinition = lspf.gotoDefinition
var TgotoDeclaration = lspf.gotoDeclaration
var TgotoTypedef = lspf.gotoTypedef
var TgotoImplementation = lspf.gotoImplementation
var TshowDiagnostics = lspf.showDiagnostics
var TshowCurrentDiag = lspf.showCurrentDiag
var TjumpToDiag = lspf.jumpToDiag
var TdiagHighlightEnable = lspf.diagHighlightEnable
var TdiagHighlightDisable = lspf.diagHighlightDisable
var TshowReferences = lspf.showReferences
var Toutline = lspf.outline
var TtextDocFormat = lspf.textDocFormat
var TincomingCalls = lspf.incomingCalls
var ToutgoingCalls = lspf.outgoingCalls
var Trename = lspf.rename
var TcodeAction = lspf.codeAction
var TsymbolSearch = lspf.symbolSearch
var Thover = lspf.hover
var TselectionExpand = lspf.selectionExpand
var TselectionShrink = lspf.selectionShrink
var TfoldDocument = lspf.foldDocument
var TlistWorkspaceFolders = lspf.listWorkspaceFolders
var TaddWorkspaceFolder = lspf.addWorkspaceFolder
var TremoveWorkspaceFolder = lspf.removeWorkspaceFolder

augroup LSPAutoCmds
  au!
  autocmd BufNewFile,BufReadPost * TaddFile(expand('<abuf>')->str2nr())
  # Note that when BufWipeOut is invoked, the current buffer may be different
  # from the buffer getting wiped out.
  autocmd BufWipeOut * TremoveFile(expand('<abuf>')->str2nr())
  if opt.lspOptions.showDiagOnStatusLine
    autocmd CursorMoved * TshowCurrentDiagInStatusLine()
  endif
augroup END

# TODO: Is it needed to shutdown all the LSP servers when exiting Vim?
# This takes some time.
# autocmd VimLeavePre * call TstopAllServers()

# LSP commands
command! -nargs=0 -bar LspShowServers call s:TshowServers()
command! -nargs=0 -bar LspShowServerCapabilities call s:TshowServerCapabilities()
command! -nargs=1 -bar LspSetTrace call TsetTraceServer(<q-args>)
command! -nargs=0 -bar LspGotoDefinition call TgotoDefinition(v:false)
command! -nargs=0 -bar LspGotoDeclaration call TgotoDeclaration(v:false)
command! -nargs=0 -bar LspGotoTypeDef call TgotoTypedef(v:false)
command! -nargs=0 -bar LspGotoImpl call TgotoImplementation(v:false)
command! -nargs=0 -bar LspPeekDefinition call TgotoDefinition(v:true)
command! -nargs=0 -bar LspPeekDeclaration call TgotoDeclaration(v:true)
command! -nargs=0 -bar LspPeekTypeDef call TgotoTypedef(v:true)
command! -nargs=0 -bar LspPeekImpl call TgotoImplementation(v:true)
command! -nargs=0 -bar LspShowSignature call LspShowSignature()
command! -nargs=0 -bar LspDiagShow call TshowDiagnostics()
command! -nargs=0 -bar LspDiagCurrent call TshowCurrentDiag()
command! -nargs=0 -bar LspDiagFirst call TjumpToDiag('first')
command! -nargs=0 -bar LspDiagNext call TjumpToDiag('next')
command! -nargs=0 -bar LspDiagPrev call TjumpToDiag('prev')
command! -nargs=0 -bar LspDiagHighlightEnable call TdiagHighlightEnable()
command! -nargs=0 -bar LspDiagHighlightDisable call TdiagHighlightDisable()
command! -nargs=0 -bar LspShowReferences call s:TshowReferences(v:false)
command! -nargs=0 -bar LspPeekReferences call s:TshowReferences(v:true)
command! -nargs=0 -bar LspHighlight call LspDocHighlight()
command! -nargs=0 -bar LspHighlightClear call LspDocHighlightClear()
command! -nargs=0 -bar LspOutline call Toutline()
command! -nargs=0 -bar -range=% LspFormat call TtextDocFormat(<range>, <line1>, <line2>)
command! -nargs=0 -bar LspOutgoingCalls call ToutgoingCalls()
command! -nargs=0 -bar LspIncomingCalls call TincomingCalls()
command! -nargs=0 -bar LspRename call Trename()
command! -nargs=0 -bar LspCodeAction call TcodeAction()
command! -nargs=? -bar LspSymbolSearch call TsymbolSearch(<q-args>)
command! -nargs=0 -bar LspHover call Thover()
command! -nargs=0 -bar LspSelectionExpand call TselectionExpand()
command! -nargs=0 -bar LspSelectionShrink call TselectionShrink()
command! -nargs=0 -bar LspFold call TfoldDocument()
command! -nargs=0 -bar LspWorkspaceListFolders call TlistWorkspaceFolders()
command! -nargs=1 -bar -complete=dir LspWorkspaceAddFolder call TaddWorkspaceFolder(<q-args>)
command! -nargs=1 -bar -complete=dir LspWorkspaceRemoveFolder call TremoveWorkspaceFolder(<q-args>)

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

  if &mousemodel =~ 'popup'
    anoremenu <silent> PopUp.L&sp.Go\ to\ Definition
	  \ :LspGotoDefinition<CR>
    anoremenu <silent> PopUp.L&sp.Go\ to\ Declaration
	  \ :LspGotoDeclaration<CR>
    anoremenu <silent> Popup.L&sp.Find\ All\ References
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
