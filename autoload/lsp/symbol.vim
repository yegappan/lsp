vim9script

# Functions for dealing with symbols.
#   - LSP symbol menu and for searching symbols across the workspace.
#   - show symbol references
#   - jump to a symbol definition, declaration, type definition or
#     implementation

import './options.vim' as opt
import './util.vim'
import './outline.vim'

# Handle keys pressed when the workspace symbol popup menu is displayed
def FilterSymbols(lspserver: dict<any>, popupID: number, key: string): bool
  var key_handled: bool = false
  var update_popup: bool = false
  var query: string = lspserver.workspaceSymbolQuery

  if key == "\<BS>" || key == "\<C-H>"
    # Erase one character from the filter text
    if query->len() >= 1
      query = query[: -2]
      update_popup = true
    endif
    key_handled = true
  elseif key == "\<C-U>"
    # clear the filter text
    query = ''
    update_popup = true
    key_handled = true
  elseif key == "\<C-F>"
        || key == "\<C-B>"
        || key == "\<PageUp>"
        || key == "\<PageDown>"
        || key == "\<C-Home>"
        || key == "\<C-End>"
        || key == "\<C-N>"
        || key == "\<C-P>"
    # scroll the popup window
    var cmd: string = 'normal! ' .. (key == "\<C-N>" ? 'j' : key == "\<C-P>" ? 'k' : key)
    win_execute(popupID, cmd)
    key_handled = true
  elseif key == "\<Up>" || key == "\<Down>"
    # Use native Vim handling for these keys
    key_handled = false
  elseif key =~ '^\f$' || key == "\<Space>"
    # Filter the names based on the typed key and keys typed before
    query ..= key
    update_popup = true
    key_handled = true
  endif

  if update_popup
    # Update the popup with the new list of symbol names
    popupID->popup_settext('')
    if query != ''
      lspserver.workspaceQuery(query)
    else
      []->setwinvar(popupID, 'LspSymbolTable')
    endif
    echo $'Symbol: {query}'
  endif

  # Update the workspace symbol query string
  lspserver.workspaceSymbolQuery = query

  if key_handled
    return true
  endif

  return popupID->popup_filter_menu(key)
enddef

# Jump to the location of a symbol selected in the popup menu
def JumpToWorkspaceSymbol(popupID: number, result: number): void
  # clear the message displayed at the command-line
  echo ''

  if result <= 0
    # popup is canceled
    return
  endif

  var symTbl: list<dict<any>> = popupID->getwinvar('LspSymbolTable', [])
  if symTbl->empty()
    return
  endif
  try
    # Save the current location in the tag stack
    util.PushCursorToTagStack()

    # if the selected file is already present in a window, then jump to it
    var fname: string = symTbl[result - 1].file
    var bufnum = fname->bufnr()
    var winList: list<number> = bufnum->win_findbuf()
    if winList->len() == 0
      # Not present in any window
      if &modified || &buftype != ''
	# the current buffer is modified or is not a normal buffer, then open
	# the file in a new window
	exe $'split {symTbl[result - 1].file}'
      else
	exe $'confirm edit {symTbl[result - 1].file}'
      endif
    else
      if bufnr() != bufnum
	var winID = fname->bufwinid()
	if winID == -1
	  # not present in the current tab page
	  winID = winList[0]
	endif
	winID->win_gotoid()
      endif
    endif
    # Set the previous cursor location mark. Instead of using setpos(), m' is
    # used so that the current location is added to the jump list.
    normal m'
    setcursorcharpos(symTbl[result - 1].pos.line + 1,
			symTbl[result - 1].pos.character + 1)
  catch
    # ignore exceptions
  endtry
enddef

# display a list of symbols from the workspace
def ShowSymbolMenu(lspserver: dict<any>, query: string)
  # Create the popup menu
  var lnum = &lines - &cmdheight - 2 - 10
  var popupAttr = {
      title: 'Workspace Symbol Search',
      wrap: false,
      pos: 'topleft',
      line: lnum,
      col: 2,
      minwidth: 60,
      minheight: 10,
      maxheight: 10,
      maxwidth: 60,
      mapping: false,
      fixed: 1,
      close: "button",
      filter: function(FilterSymbols, [lspserver]),
      callback: JumpToWorkspaceSymbol
  }
  lspserver.workspaceSymbolPopup = popup_menu([], popupAttr)
  lspserver.workspaceSymbolQuery = query
  prop_type_add('lspworkspacesymbol',
			{bufnr: lspserver.workspaceSymbolPopup->winbufnr(),
			 highlight: 'Title'})
  echo $'Symbol: {query}'
enddef

# Convert a file name to <filename> (<dirname>) format.
# Make sure the popup does't occupy the entire screen by reducing the width.
def MakeMenuName(popupWidth: number, fname: string): string
  var filename: string = fname->fnamemodify(':t')
  var flen: number = filename->len()
  var dirname: string = fname->fnamemodify(':h')

  if fname->len() > popupWidth && flen < popupWidth
    # keep the full file name and reduce directory name length
    # keep some characters at the beginning and end (equally).
    # 6 spaces are used for "..." and " ()"
    var dirsz = (popupWidth - flen - 6) / 2
    dirname = dirname[: dirsz] .. '...' .. dirname[-dirsz : ]
  endif
  var str: string = filename
  if dirname != '.'
    str ..= $' ({dirname}/)'
  endif
  return str
enddef

# process the 'workspace/symbol' reply from the LSP server
# Result: SymbolInformation[] | null
export def WorkspaceSymbolPopup(lspserver: dict<any>, query: string,
				symInfo: list<dict<any>>)
  var symbols: list<dict<any>> = []
  var symbolType: string
  var fileName: string
  var r: dict<dict<number>>
  var symName: string

  # Create a symbol popup menu if it is not present
  if lspserver.workspaceSymbolPopup->winbufnr() == -1
    ShowSymbolMenu(lspserver, query)
  endif

  for symbol in symInfo
    if !symbol->has_key('location')
      # ignore entries without location information
      continue
    endif

    # interface SymbolInformation
    fileName = util.LspUriToFile(symbol.location.uri)
    r = symbol.location.range

    symName = symbol.name
    if symbol->has_key('containerName') && symbol.containerName != ''
      symName = $'{symbol.containerName}::{symName}'
    endif
    symName ..= $' [{SymbolKindToName(symbol.kind)}]'
    symName ..= ' ' .. MakeMenuName(
		lspserver.workspaceSymbolPopup->popup_getpos().core_width,
		fileName)

    symbols->add({name: symName,
			file: fileName,
			pos: r.start})
  endfor
  symbols->setwinvar(lspserver.workspaceSymbolPopup, 'LspSymbolTable')
  lspserver.workspaceSymbolPopup->popup_settext(
				symbols->copy()->mapnew('v:val.name'))
enddef

# map the LSP symbol kind number to string
export def SymbolKindToName(symkind: number): string
  var symbolMap: list<string> = ['', 'File', 'Module', 'Namespace', 'Package',
	'Class', 'Method', 'Property', 'Field', 'Constructor', 'Enum',
	'Interface', 'Function', 'Variable', 'Constant', 'String', 'Number',
	'Boolean', 'Array', 'Object', 'Key', 'Null', 'EnumMember', 'Struct',
	'Event', 'Operator', 'TypeParameter']
  if symkind > 26
    return ''
  endif
  return symbolMap[symkind]
enddef

def UpdatePeekFilePopup(lspserver: dict<any>, refs: list<dict<any>>)
  if lspserver.peekSymbolPopup->winbufnr() == -1
    return
  endif

  lspserver.peekSymbolFilePopup->popup_close()

  var n = line('.', lspserver.peekSymbolPopup) - 1
  var fname: string = util.LspUriToFile(refs[n].uri)

  var bnr: number = fname->bufnr()
  if bnr == -1
    bnr = fname->bufadd()
  endif

  var popupAttrs = {
    title: $"{fname->fnamemodify(':t')} ({fname->fnamemodify(':h')})",
    wrap: false,
    fixed: true,
    minheight: 10,
    maxheight: 10,
    minwidth: winwidth(0) - 38,
    maxwidth: winwidth(0) - 38,
    cursorline: true,
    border: [],
    mapping: false,
    line: 'cursor+1',
    col: 1
  }

  lspserver.peekSymbolFilePopup = popup_create(bnr, popupAttrs)
  var cmds =<< trim eval END
    [{refs[n].range.start.line + 1}, 1]->cursor()
    normal! z.
  END
  win_execute(lspserver.peekSymbolFilePopup, cmds)

  lspserver.peekSymbolFilePopup->clearmatches()
  var start_col = util.GetLineByteFromPos(bnr,
					refs[n].range.start) + 1
  var end_col = util.GetLineByteFromPos(bnr, refs[n].range.end)
  var pos = [[refs[n].range.start.line + 1,
	     start_col, end_col - start_col + 1]]
  matchaddpos('Search', pos, 10, -1, {window: lspserver.peekSymbolFilePopup})
enddef

def RefPopupFilter(lspserver: dict<any>, refs: list<dict<any>>,
                       popup_id: number, key: string): bool
  popup_filter_menu(popup_id, key)
  if lspserver.peekSymbolPopup->winbufnr() == -1
    if lspserver.peekSymbolFilePopup->winbufnr() != -1
      lspserver.peekSymbolFilePopup->popup_close()
    endif
    lspserver.peekSymbolPopup = -1
    lspserver.peekSymbolFilePopup = -1
  else
    UpdatePeekFilePopup(lspserver, refs)
  endif
  return true
enddef

def RefPopupCallback(lspserver: dict<any>, refs: list<dict<any>>,
		     popup_id: number, selIdx: number)
  if lspserver.peekSymbolFilePopup->winbufnr() != -1
    lspserver.peekSymbolFilePopup->popup_close()
  endif
  lspserver.peekSymbolPopup = -1
  if selIdx != -1
    var fname: string = util.LspUriToFile(refs[selIdx - 1].uri)
    util.PushCursorToTagStack()
    util.JumpToLspLocation(refs[selIdx - 1], '')
  endif
enddef

# Display the references in a popup menu.  Display the corresponding file in
# an another popup window.
def PeekReferences(lspserver: dict<any>, refs: list<dict<any>>)
  if lspserver.peekSymbolPopup->winbufnr() != -1
    # If the symbol popup window is already present, close it.
    lspserver.peekSymbolPopup->popup_close()
  endif

  var w: number = &columns
  var fnamelen = float2nr(w * 0.4)

  var menuItems: list<string> = []
  for loc in refs
    var fname: string = util.LspUriToFile(loc.uri)
    var bnr: number = fname->bufnr()
    if bnr == -1
      bnr = fname->bufadd()
    endif
    if !bnr->bufloaded()
      bnr->bufload()
    endif

    var text: string = bnr->getbufline(loc.range.start.line + 1)[0]
    var lnum = loc.range.start.line + 1
    menuItems->add($'{lnum}: {text}')
  endfor

  var popupAttrs = {
    title: 'References',
    wrap: false,
    pos: 'topleft',
    line: 'cursor+1',
    col: winwidth(0) - 34,
    minheight: 10,
    maxheight: 10,
    minwidth: 30,
    maxwidth: 30,
    mapping: false,
    fixed: true,
    filter: function(RefPopupFilter, [lspserver, refs]),
    callback: function(RefPopupCallback, [lspserver, refs])
  }
  lspserver.peekSymbolPopup = popup_menu(menuItems, popupAttrs)
  UpdatePeekFilePopup(lspserver, refs)
enddef

# Display or peek symbol references in a location list
export def ShowReferences(lspserver: dict<any>, refs: list<dict<any>>, peekSymbol: bool)
  if peekSymbol
    PeekReferences(lspserver, refs)
    return
  endif

  # create a location list with the location of the references
  var qflist: list<dict<any>> = []
  for loc in refs
    var fname: string = util.LspUriToFile(loc.uri)
    var bnr: number = fname->bufnr()
    if bnr == -1
      bnr = fname->bufadd()
    endif
    if !bnr->bufloaded()
      bnr->bufload()
    endif
    var text: string = bnr->getbufline(loc.range.start.line + 1)[0]
						->trim("\t ", 1)
    qflist->add({filename: fname,
			lnum: loc.range.start.line + 1,
			col: util.GetLineByteFromPos(bnr, loc.range.start) + 1,
			text: text})
  endfor

  var save_winid = win_getid()
  setloclist(0, [], ' ', {title: 'Symbol Reference', items: qflist})
  var mods: string = ''
  exe $'{mods} lopen'
  if !opt.lspOptions.keepFocusInReferences
    save_winid->win_gotoid()
  endif
enddef

# Key filter callback function used for the symbol popup window.
# Vim doesn't close the popup window when the escape key is pressed.
# This is function supports that.
def SymbolFilterCB(lspserver: dict<any>, id: number, key: string): bool
  if key == "\<Esc>"
    lspserver.peekSymbolPopup->popup_close()
    return true
  endif

  return false
enddef

# Display the file specified by LSP 'location' in a popup window and highlight
# the range in 'location'.
def PeekSymbolLocation(lspserver: dict<any>, location: dict<any>)
  var fname = util.LspUriToFile(location.uri)
  var bnum = fname->bufadd()
  if bnum == 0
    # Failed to create or find a buffer
    return
  endif
  silent! bnum->bufload()

  if lspserver.peekSymbolPopup->winbufnr() != -1
    # If the symbol popup window is already present, close it.
    lspserver.peekSymbolPopup->popup_close()
  endif
  var CbFunc = function(SymbolFilterCB, [lspserver])
  var popupAttrs = {
    title: $"{fnamemodify(fname, ':t')} ({fnamemodify(fname, ':h')})",
    wrap: false,
    moved: 'any',
    minheight: 10,
    maxheight: 10,
    minwidth: 10,
    maxwidth: 60,
    cursorline: true,
    border: [],
    mapping: false,
    filter: CbFunc
  }
  lspserver.peekSymbolPopup = popup_atcursor(bnum, popupAttrs)

  # Highlight the symbol name and center the line in the popup
  var pwid = lspserver.peekSymbolPopup
  var pwbuf = pwid->winbufnr()
  var pos: list<number> = []
  var start_col: number
  var end_col: number
  start_col = util.GetLineByteFromPos(pwbuf, location.range.start) + 1
  end_col = util.GetLineByteFromPos(pwbuf, location.range.end) + 1
  pos->add(location.range.start.line + 1)
  pos->extend([start_col, end_col - start_col])
  matchaddpos('Search', [pos], 10, 101, {window: pwid})
  var cmds =<< trim eval END
    [{location.range.start.line + 1}, 1]->cursor()
    normal! z.
  END
  win_execute(pwid, cmds, 'silent!')
enddef

# Jump to the definition, declaration or implementation of a symbol.
# Also, used to peek at the definition, declaration or implementation of a
# symbol.
export def GotoSymbol(lspserver: dict<any>, location: dict<any>,
		      peekSymbol: bool, cmdmods: string)
  if peekSymbol
    PeekSymbolLocation(lspserver, location)
  else
    # Save the current cursor location in the tag stack.
    util.PushCursorToTagStack()
    util.JumpToLspLocation(location, cmdmods)
  endif
enddef

# Process the LSP server reply message for a 'textDocument/definition' request
# and return a list of Dicts in a format accepted by the 'tagfunc' option.
export def TagFunc(lspserver: dict<any>,
			taglocations: list<dict<any>>,
			pat: string): list<dict<any>>
  var retval: list<dict<any>>

  for tagloc in taglocations
    var tagitem = {}
    tagitem.name = pat
    tagitem.filename = util.LspUriToFile(tagloc.uri)
    tagitem.cmd = (tagloc.range.start.line + 1)->string()
    retval->add(tagitem)
  endfor

  return retval
enddef

# process SymbolInformation[]
def ProcessSymbolInfoTable(symbolInfoTable: list<dict<any>>,
				symbolTypeTable: dict<list<dict<any>>>,
				symbolLineTable: list<dict<any>>)
  var fname: string
  var symbolType: string
  var name: string
  var r: dict<dict<number>>
  var symInfo: dict<any>

  for syminfo in symbolInfoTable
    fname = util.LspUriToFile(syminfo.location.uri)
    symbolType = SymbolKindToName(syminfo.kind)
    name = syminfo.name
    if syminfo->has_key('containerName')
      if syminfo.containerName != ''
	name ..= $' [{syminfo.containerName}]'
      endif
    endif
    r = syminfo.location.range

    if !symbolTypeTable->has_key(symbolType)
      symbolTypeTable[symbolType] = []
    endif
    symInfo = {name: name, range: r}
    symbolTypeTable[symbolType]->add(symInfo)
    symbolLineTable->add(symInfo)
  endfor
enddef

# process DocumentSymbol[]
def ProcessDocSymbolTable(docSymbolTable: list<dict<any>>,
				symbolTypeTable: dict<list<dict<any>>>,
				symbolLineTable: list<dict<any>>)
  var symbolType: string
  var name: string
  var r: dict<dict<number>>
  var symInfo: dict<any>
  var symbolDetail: string
  var childSymbols: dict<list<dict<any>>>

  for syminfo in docSymbolTable
    name = syminfo.name
    symbolType = SymbolKindToName(syminfo.kind)
    r = syminfo.range
    if syminfo->has_key('detail')
      symbolDetail = syminfo.detail
    endif
    if !symbolTypeTable->has_key(symbolType)
      symbolTypeTable[symbolType] = []
    endif
    childSymbols = {}
    if syminfo->has_key('children')
      ProcessDocSymbolTable(syminfo.children, childSymbols, symbolLineTable)
    endif
    symInfo = {name: name, range: r, detail: symbolDetail,
						children: childSymbols}
    symbolTypeTable[symbolType]->add(symInfo)
    symbolLineTable->add(symInfo)
  endfor
enddef

# process the 'textDocument/documentSymbol' reply from the LSP server
# Open a symbols window and display the symbols as a tree
# Result: DocumentSymbol[] | SymbolInformation[] | null
export def DocSymbolReply(fname: string, lspserver: dict<any>, docsymbol: any)
  var symbolTypeTable: dict<list<dict<any>>> = {}
  var symbolLineTable: list<dict<any>> = []

  if docsymbol->empty()
    # No symbols defined for this file. Clear the outline window.
    outline.UpdateOutlineWindow(fname, symbolTypeTable, symbolLineTable)
    return
  endif

  if docsymbol[0]->has_key('location')
    # SymbolInformation[]
    ProcessSymbolInfoTable(docsymbol, symbolTypeTable, symbolLineTable)
  else
    # DocumentSymbol[]
    ProcessDocSymbolTable(docsymbol, symbolTypeTable, symbolLineTable)
  endif

  # sort the symbols by line number
  symbolLineTable->sort((a, b) => a.range.start.line - b.range.start.line)
  outline.UpdateOutlineWindow(fname, symbolTypeTable, symbolLineTable)
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
