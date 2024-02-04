vim9script

# Functions for dealing with symbols.
#   - LSP symbol menu and for searching symbols across the workspace.
#   - show locations
#   - jump to a symbol definition, declaration, type definition or
#     implementation

import './options.vim' as opt
import './util.vim'
import './outline.vim'

# Initialize the highlight group and the text property type used for
# document symbol search
export def InitOnce()
  # Use a high priority value to override other highlights in the line
  hlset([
    {name: 'LspSymbolName', default: true, linksto: 'Search'},
    {name: 'LspSymbolRange', default: true, linksto: 'Visual'}
  ])
  prop_type_add('LspSymbolNameProp', {highlight: 'LspSymbolName',
				       combine: false,
				       override: true,
				       priority: 201})
  prop_type_add('LspSymbolRangeProp', {highlight: 'LspSymbolRange',
				       combine: false,
				       override: true,
				       priority: 200})
enddef

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
      lspserver.workspaceQuery(query, false)
    else
      []->setwinvar(popupID, 'LspSymbolTable')
    endif
    :echo $'Symbol: {query}'
  endif

  # Update the workspace symbol query string
  lspserver.workspaceSymbolQuery = query

  if key_handled
    return true
  endif

  return popupID->popup_filter_menu(key)
enddef

# Jump to the location of a symbol selected in the popup menu
def JumpToWorkspaceSymbol(cmdmods: string, popupID: number, result: number): void
  # clear the message displayed at the command-line
  :echo ''

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
    var bnr = fname->bufnr()
    if cmdmods->empty()
      var winList: list<number> = bnr->win_findbuf()
      if winList->empty()
	# Not present in any window
	if &modified || &buftype != ''
	  # the current buffer is modified or is not a normal buffer, then
	  # open the file in a new window
	  exe $'split {symTbl[result - 1].file}'
	else
	  exe $'confirm edit {symTbl[result - 1].file}'
	endif
      else
	# If the target buffer is opened in the current window, then don't
	# change the window.
	if bufnr() != bnr
	  # If the target buffer is opened in a window in the current tab
	  # page, then use it.
	  var winID = fname->bufwinid()
	  if winID == -1
	    # not present in the current tab page.  Use the first window.
	    winID = winList[0]
	  endif
	  winID->win_gotoid()
	endif
      endif
    else
      exe $'{cmdmods} split {symTbl[result - 1].file}'
    endif
    # Set the previous cursor location mark. Instead of using setpos(), m' is
    # used so that the current location is added to the jump list.
    :normal m'
    setcursorcharpos(symTbl[result - 1].pos.line + 1,
		     util.GetCharIdxWithoutCompChar(bufnr(),
						    symTbl[result - 1].pos) + 1)
    :normal! zv
  catch
    # ignore exceptions
  endtry
enddef

# display a list of symbols from the workspace
def ShowSymbolMenu(lspserver: dict<any>, query: string, cmdmods: string)
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
      close: 'button',
      filter: function(FilterSymbols, [lspserver]),
      callback: function('JumpToWorkspaceSymbol', [cmdmods])
  }
  lspserver.workspaceSymbolPopup = popup_menu([], popupAttr)
  lspserver.workspaceSymbolQuery = query
  prop_type_add('lspworkspacesymbol',
			{bufnr: lspserver.workspaceSymbolPopup->winbufnr(),
			 highlight: 'Title'})
  :echo $'Symbol: {query}'
enddef

# Convert a file name to <filename> (<dirname>) format.
# Make sure the popup doesn't occupy the entire screen by reducing the width.
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
				symInfo: list<dict<any>>, cmdmods: string)
  var symbols: list<dict<any>> = []
  var symbolType: string
  var fileName: string
  var symName: string

  # Create a symbol popup menu if it is not present
  if lspserver.workspaceSymbolPopup->winbufnr() == -1
    ShowSymbolMenu(lspserver, query, cmdmods)
  endif

  for symbol in symInfo
    if !symbol->has_key('location')
      # ignore entries without location information
      continue
    endif

    # interface SymbolInformation
    fileName = util.LspUriToFile(symbol.location.uri)

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
			pos: symbol.location.range.start})
  endfor
  symbols->setwinvar(lspserver.workspaceSymbolPopup, 'LspSymbolTable')
  lspserver.workspaceSymbolPopup->popup_settext(
				symbols->copy()->mapnew('v:val.name'))
enddef

# map the LSP symbol kind number to string
export def SymbolKindToName(symkind: number): string
  var symbolMap: list<string> = [
    '',
    'File',
    'Module',
    'Namespace',
    'Package',
    'Class',
    'Method',
    'Property',
    'Field',
    'Constructor',
    'Enum',
    'Interface',
    'Function',
    'Variable',
    'Constant',
    'String',
    'Number',
    'Boolean',
    'Array',
    'Object',
    'Key',
    'Null',
    'EnumMember',
    'Struct',
    'Event',
    'Operator',
    'TypeParameter'
  ]
  if symkind > 26
    return ''
  endif
  return symbolMap[symkind]
enddef

def UpdatePeekFilePopup(lspserver: dict<any>, locations: list<dict<any>>)
  if lspserver.peekSymbolPopup->winbufnr() == -1
    return
  endif

  lspserver.peekSymbolFilePopup->popup_close()

  var n = line('.', lspserver.peekSymbolPopup) - 1
  var [uri, range] = util.LspLocationParse(locations[n])
  var fname: string = util.LspUriToFile(uri)

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
  var rstart = range.start
  var cmds =<< trim eval END
    :setlocal number
    [{rstart.line + 1}, 1]->cursor()
    :normal! z.
  END
  win_execute(lspserver.peekSymbolFilePopup, cmds)

  lspserver.peekSymbolFilePopup->clearmatches()
  var start_col = util.GetLineByteFromPos(bnr, rstart) + 1
  var end_col = util.GetLineByteFromPos(bnr, range.end)
  var pos = [[rstart.line + 1,
	     start_col, end_col - start_col + 1]]
  matchaddpos('Search', pos, 10, -1, {window: lspserver.peekSymbolFilePopup})
enddef

def LocPopupFilter(lspserver: dict<any>, locations: list<dict<any>>,
                   popup_id: number, key: string): bool
  popup_filter_menu(popup_id, key)
  if lspserver.peekSymbolPopup->winbufnr() == -1
    if lspserver.peekSymbolFilePopup->winbufnr() != -1
      lspserver.peekSymbolFilePopup->popup_close()
    endif
    lspserver.peekSymbolPopup = -1
    lspserver.peekSymbolFilePopup = -1
  else
    UpdatePeekFilePopup(lspserver, locations)
  endif
  return true
enddef

def LocPopupCallback(lspserver: dict<any>, locations: list<dict<any>>,
		     popup_id: number, selIdx: number)
  if lspserver.peekSymbolFilePopup->winbufnr() != -1
    lspserver.peekSymbolFilePopup->popup_close()
  endif
  lspserver.peekSymbolPopup = -1
  if selIdx != -1
    util.PushCursorToTagStack()
    util.JumpToLspLocation(locations[selIdx - 1], '')
  endif
enddef

# Display the locations in a popup menu.  Display the corresponding file in
# an another popup window.
def PeekLocations(lspserver: dict<any>, locations: list<dict<any>>,
                  title: string)
  if lspserver.peekSymbolPopup->winbufnr() != -1
    # If the symbol popup window is already present, close it.
    lspserver.peekSymbolPopup->popup_close()
  endif

  var w: number = &columns
  var fnamelen = float2nr(w * 0.4)

  var curlnum = line('.')
  var symIdx = 1
  var curSymIdx = 1
  var menuItems: list<string> = []
  for loc in locations
    var [uri, range] = util.LspLocationParse(loc)
    var fname: string = util.LspUriToFile(uri)
    var bnr: number = fname->bufnr()
    if bnr == -1
      bnr = fname->bufadd()
    endif
    :silent! bnr->bufload()

    var lnum = range.start.line + 1
    var text: string = bnr->getbufline(lnum)->get(0, '')
    menuItems->add($'{lnum}: {text}')

    if lnum == curlnum
      curSymIdx = symIdx
    endif
    symIdx += 1
  endfor

  var popupAttrs = {
    title: title,
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
    filter: function(LocPopupFilter, [lspserver, locations]),
    callback: function(LocPopupCallback, [lspserver, locations])
  }
  lspserver.peekSymbolPopup = popup_menu(menuItems, popupAttrs)
  # Select the current symbol in the menu
  var cmds =<< trim eval END
    [{curSymIdx}, 1]->cursor()
  END
  win_execute(lspserver.peekSymbolPopup, cmds, 'silent!')
  UpdatePeekFilePopup(lspserver, locations)
enddef

export def ShowLocations(lspserver: dict<any>, locations: list<dict<any>>,
                         peekSymbol: bool, title: string)
  if peekSymbol
    PeekLocations(lspserver, locations, title)
    return
  endif

  # create a loclist the location of the locations
  var qflist: list<dict<any>> = []
  for loc in locations
    var [uri, range] = util.LspLocationParse(loc)
    var fname: string = util.LspUriToFile(uri)
    var bnr: number = fname->bufnr()
    if bnr == -1
      bnr = fname->bufadd()
    endif
    :silent! bnr->bufload()
    var rstart = range.start
    var text: string = bnr->getbufline(rstart.line + 1)->get(0, '')->trim("\t ", 1)
    qflist->add({filename: fname,
			lnum: rstart.line + 1,
			col: util.GetLineByteFromPos(bnr, rstart) + 1,
			text: text})
  endfor

  var save_winid = win_getid()

  if opt.lspOptions.useQuickfixForLocations
    setqflist([], ' ', {title: title, items: qflist})
    var mods: string = ''
    exe $'{mods} copen'
  else
    setloclist(0, [], ' ', {title: title, items: qflist})
    var mods: string = ''
    exe $'{mods} lopen'
  endif

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

# Display the file specified by LSP "LocationLink" in a popup window and
# highlight the range in "location".
def PeekSymbolLocation(lspserver: dict<any>, location: dict<any>)
  var [uri, range] = util.LspLocationParse(location)
  var fname = util.LspUriToFile(uri)
  var bnum = fname->bufadd()
  if bnum == 0
    # Failed to create or find a buffer
    return
  endif
  :silent! bnum->bufload()

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
  var rstart = range.start
  start_col = util.GetLineByteFromPos(pwbuf, rstart) + 1
  end_col = util.GetLineByteFromPos(pwbuf, range.end) + 1
  pos->add(rstart.line + 1)
  pos->extend([start_col, end_col - start_col])
  matchaddpos('Search', [pos], 10, 101, {window: pwid})
  var cmds =<< trim eval END
    :setlocal number
    [{rstart.line + 1}, 1]->cursor()
    :normal! z.
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

    var [uri, range] = util.LspLocationParse(tagloc)
    tagitem.filename = util.LspUriToFile(uri)
    var bnr = util.LspUriToBufnr(uri)
    var rstart = range.start
    var startByteIdx = util.GetLineByteFromPos(bnr, rstart)
    tagitem.cmd = $"/\\%{rstart.line + 1}l\\%{startByteIdx + 1}c"

    retval->add(tagitem)
  endfor

  return retval
enddef

# process SymbolInformation[]
def ProcessSymbolInfoTable(lspserver: dict<any>,
			   bnr: number,
			   symbolInfoTable: list<dict<any>>,
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
    lspserver.decodeRange(bnr, r)

    if !symbolTypeTable->has_key(symbolType)
      symbolTypeTable[symbolType] = []
    endif
    symInfo = {name: name, range: r}
    symbolTypeTable[symbolType]->add(symInfo)
    symbolLineTable->add(symInfo)
  endfor
enddef

# process DocumentSymbol[]
def ProcessDocSymbolTable(lspserver: dict<any>,
			  bnr: number,
			  docSymbolTable: list<dict<any>>,
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
    r = syminfo.selectionRange
    lspserver.decodeRange(bnr, r)
    if syminfo->has_key('detail')
      symbolDetail = syminfo.detail
    endif
    if !symbolTypeTable->has_key(symbolType)
      symbolTypeTable[symbolType] = []
    endif
    childSymbols = {}
    if syminfo->has_key('children')
      ProcessDocSymbolTable(lspserver, bnr, syminfo.children, childSymbols,
			    symbolLineTable)
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
export def DocSymbolOutline(lspserver: dict<any>, docSymbol: any, fname: string)
  var bnr = fname->bufnr()
  var symbolTypeTable: dict<list<dict<any>>> = {}
  var symbolLineTable: list<dict<any>> = []

  if docSymbol->empty()
    # No symbols defined for this file. Clear the outline window.
    outline.UpdateOutlineWindow(fname, symbolTypeTable, symbolLineTable)
    return
  endif

  if docSymbol[0]->has_key('location')
    # SymbolInformation[]
    ProcessSymbolInfoTable(lspserver, bnr, docSymbol, symbolTypeTable,
			   symbolLineTable)
  else
    # DocumentSymbol[]
    ProcessDocSymbolTable(lspserver, bnr, docSymbol, symbolTypeTable,
			  symbolLineTable)
  endif

  # sort the symbols by line number
  symbolLineTable->sort((a, b) => a.range.start.line - b.range.start.line)
  outline.UpdateOutlineWindow(fname, symbolTypeTable, symbolLineTable)
enddef

# Process the list of symbols (LSP interface "SymbolInformation") in
# "symbolInfoTable". For each symbol, create the name to display in the popup
# menu along with the symbol range and return the List.
def GetSymbolsInfoTable(lspserver: dict<any>,
			bnr: number,
			symbolInfoTable: list<dict<any>>): list<dict<any>>
  var symbolTable: list<dict<any>> = []
  var symbolType: string
  var name: string
  var containerName: string
  var r: dict<dict<number>>

  for syminfo in symbolInfoTable
    symbolType = SymbolKindToName(syminfo.kind)
    name = $'{symbolType} : {syminfo.name}'
    if syminfo->has_key('containerName') && !syminfo.containerName->empty()
      name ..= $' [{syminfo.containerName}]'
    endif
    r = syminfo.location.range
    lspserver.decodeRange(bnr, r)

    symbolTable->add({name: name, range: r, selectionRange: {}})
  endfor

  return symbolTable
enddef

# Process the list of symbols (LSP interface "DocumentSymbol") in
# "docSymbolTable". For each symbol, create the name to display in the popup
# menu along with the symbol range and return the List in "symbolTable"
def GetSymbolsDocSymbol(lspserver: dict<any>,
			bnr: number,
			docSymbolTable: list<dict<any>>,
			symbolTable: list<dict<any>>,
			parentName: string = '')
  var symbolType: string
  var name: string
  var r: dict<dict<number>>
  var sr: dict<dict<number>>
  var symInfo: dict<any>

  for syminfo in docSymbolTable
    var symName = syminfo.name
    symbolType = SymbolKindToName(syminfo.kind)->tolower()
    sr = syminfo.selectionRange
    lspserver.decodeRange(bnr, sr)
    r = syminfo.range
    lspserver.decodeRange(bnr, r)
    name = $'{symbolType} : {symName}'
    if parentName != ''
      name ..= $' [{parentName}]'
    endif
    # TODO: Should include syminfo.detail? Will it clutter the menu?
    symInfo = {name: name, range: r, selectionRange: sr}
    symbolTable->add(symInfo)

    if syminfo->has_key('children')
      # Process all the child symbols
      GetSymbolsDocSymbol(lspserver, bnr, syminfo.children, symbolTable,
			  symName)
    endif
  endfor
enddef

# Highlight the name and the range of lines for the symbol at symTbl[symIdx]
def SymbolHighlight(symTbl: list<dict<any>>, symIdx: number)
  prop_remove({type: 'LspSymbolNameProp', all: true})
  prop_remove({type: 'LspSymbolRangeProp', all: true})
  if symTbl->empty()
    return
  endif

  var r = symTbl[symIdx].range
  if r->empty()
    return
  endif
  var rangeStart = r.start
  var rangeEnd = r.end
  var start_lnum = rangeStart.line + 1
  var start_col = rangeStart.character + 1
  var end_lnum = rangeEnd.line + 1
  var end_col: number
  var last_lnum = line('$')
  if end_lnum > line('$')
    end_lnum = last_lnum
    end_col = col([last_lnum, '$'])
  else
    end_col = rangeEnd.character + 1
  endif
  prop_add(start_lnum, start_col,
	   {type: 'LspSymbolRangeProp',
	    end_lnum: end_lnum,
	    end_col: end_col})
  cursor(start_lnum, 1)
  :normal! z.

  var sr = symTbl[symIdx].selectionRange
  if sr->empty()
    return
  endif
  rangeStart = sr.start
  rangeEnd = sr.end
  prop_add(rangeStart.line + 1, 1,
	   {type: 'LspSymbolNameProp',
	    start_col: rangeStart.character + 1,
	    end_lnum: rangeEnd.line + 1,
	    end_col: rangeEnd.character + 1})
enddef

# Callback invoked when an item is selected in the symbol popup menu
#   "symTbl" - list of symbols
#   "symInputPopup" - Symbol search input popup window ID
#   "save_curpos" - Cursor position before invoking the symbol search.  If the
#		    symbol search is canceled, restore the cursor to this
#		    position.
def SymbolMenuItemSelected(symPopupMenu: number,
			   result: number)
  var symTblFiltered = symPopupMenu->getwinvar('symbolTableFiltered', [])
  var symInputPopup = symPopupMenu->getwinvar('symbolInputPopup', 0)
  var save_curpos = symPopupMenu->getwinvar('saveCurPos', [])

  # Restore the cursor to the location where the command was invoked
  setpos('.', save_curpos)

  if result > 0
    # A symbol is selected in the popup menu

    # Set the previous cursor location mark. Instead of using setpos(), m' is
    # used so that the current location is added to the jump list.
    :normal m'

    # Jump to the selected symbol location
    var r = symTblFiltered[result - 1].selectionRange
    if r->empty()
      # SymbolInformation doesn't have the selectionRange field
      r = symTblFiltered[result - 1].range
    endif
    setcursorcharpos(r.start.line + 1,
		     util.GetCharIdxWithoutCompChar(bufnr(), r.start) + 1)
    :normal! zv
  endif
  symInputPopup->popup_close()
  prop_remove({type: 'LspSymbolNameProp', all: true})
  prop_remove({type: 'LspSymbolRangeProp', all: true})
enddef

# Key filter function for the symbol popup menu.
def SymbolMenuFilterKey(symPopupMenu: number,
			key: string): bool
  var keyHandled = true
  var updateInputPopup = false
  var inputText = symPopupMenu->getwinvar('inputText', '')
  var symInputPopup = symPopupMenu->getwinvar('symbolInputPopup', 0)

  if key == "\<BS>" || key == "\<C-H>"
    # Erase a character in the input popup
    if inputText->len() >= 1
      inputText = inputText[: -2]
      updateInputPopup = true
    else
      keyHandled = false
    endif
  elseif key == "\<C-U>"
    # Erase all the characters in the input popup
    inputText = ''
    updateInputPopup = true
  elseif key == "\<tab>"
      || key == "\<C-n>"
      || key == "\<Down>"
      || key == "\<ScrollWheelDown>"
    var ln = getcurpos(symPopupMenu)[1]
    win_execute(symPopupMenu, "normal! j")
    if ln == getcurpos(symPopupMenu)[1]
      win_execute(symPopupMenu, "normal! gg")
    endif
  elseif key == "\<S-tab>"
      || key == "\<C-p>"
      || key == "\<Up>"
      || key == "\<ScrollWheelUp>"
    var ln = getcurpos(symPopupMenu)[1]
    win_execute(symPopupMenu, "normal! k")
    if ln == getcurpos(symPopupMenu)[1]
      win_execute(symPopupMenu, "normal! G")
    endif
  elseif key == "\<PageDown>"
    win_execute(symPopupMenu, "normal! \<C-d>")
  elseif key == "\<PageUp>"
    win_execute(symPopupMenu, "normal! \<C-u>")
  elseif key == "\<C-F>"
      || key == "\<C-B>"
      || key == "\<C-Home>"
      || key == "\<C-End>"
    win_execute(symPopupMenu, $"normal! {key}")
  elseif key =~ '^\k$'
    # A keyword character is typed.  Add to the input text and update the
    # popup
    inputText ..= key
    updateInputPopup = true
  else
    keyHandled = false
  endif

  var symTblFiltered: list<dict<any>> = []
  symTblFiltered = symPopupMenu->getwinvar('symbolTableFiltered', [])

  if updateInputPopup
    # Update the input popup with the new text and update the symbol popup
    # window with the matching symbol names.
    symInputPopup->popup_settext(inputText)

    var symbolTable = symPopupMenu->getwinvar('symbolTable')
    symTblFiltered = symbolTable->deepcopy()
    var symbolMatchPos: list<list<number>> = []

    # Get the list of symbols fuzzy matching the entered text
    if inputText != ''
      var t = symTblFiltered->matchfuzzypos(inputText, {key: 'name'})
      symTblFiltered = t[0]
      symbolMatchPos = t[1]
    endif

    var popupText: list<dict<any>>
    var text: list<dict<any>>
    if !symbolMatchPos->empty()
      # Generate a list of symbol names and the corresponding text properties
      # to highlight the matching characters.
      popupText = symTblFiltered->mapnew((idx, val): dict<any> => ({
	text: val.name,
	props: symbolMatchPos[idx]->mapnew((_, w: number): dict<any> => ({
	  col: w + 1,
	  length: 1,
	  type: 'LspSymbolMatch'}
        ))}
      ))
    else
      popupText = symTblFiltered->mapnew((idx, val): dict<string> => {
	return {text: val.name}
      })
    endif
    symPopupMenu->popup_settext(popupText)

    # Select the first symbol and highlight the corresponding text range
    win_execute(symPopupMenu, 'cursor(1, 1)')
    SymbolHighlight(symTblFiltered, 0)
  endif

  # Save the filtered symbol table and the search text in popup window
  # variables
  setwinvar(symPopupMenu, 'inputText', inputText)
  setwinvar(symPopupMenu, 'symbolTableFiltered', symTblFiltered)

  if !keyHandled
    # Use the default handler for the key
    symPopupMenu->popup_filter_menu(key)
  endif

  # Highlight the name and range of the selected symbol
  var lnum = line('.', symPopupMenu) - 1
  if lnum >= 0
    SymbolHighlight(symTblFiltered, lnum)
  endif

  return true
enddef

# Display the symbols popup menu
def SymbolPopupMenu(symbolTable: list<dict<any>>)
  var curLine = line('.')
  var curSymIdx = 0

  # Get the names of all the symbols.  Also get the index of the symbol under
  # the cursor.
  var symNames = symbolTable->mapnew((idx, val): string => {
    var r = val.range
    if !r->empty() && curSymIdx == 0
      if curLine >= r.start.line + 1 && curLine <= r.end.line + 1
	curSymIdx = idx
      endif
    endif
    return val.name
  })

  var symInputPopupAttr = {
    title: 'Select Symbol',
    wrap: false,
    pos: 'topleft',
    line: &lines - 14,
    col: 10,
    minwidth: 60,
    minheight: 1,
    maxheight: 1,
    maxwidth: 60,
    fixed: 1,
    close: 'button',
    border: []
  }
  var symInputPopup = popup_create('', symInputPopupAttr)

  var symNamesPopupattr = {
    wrap: false,
    pos: 'topleft',
    line: &lines - 11,
    col: 10,
    minwidth: 60,
    minheight: 10,
    maxheight: 10,
    maxwidth: 60,
    fixed: 1,
    border: [0, 0, 0, 0],
    callback: SymbolMenuItemSelected,
    filter: SymbolMenuFilterKey,
  }
  var symPopupMenu = popup_menu(symNames, symNamesPopupattr)

  # Save the state in the popup menu window variables
  setwinvar(symPopupMenu, 'symbolTable', symbolTable)
  setwinvar(symPopupMenu, 'symbolTableFiltered', symbolTable->deepcopy())
  setwinvar(symPopupMenu, 'symbolInputPopup', symInputPopup)
  setwinvar(symPopupMenu, 'saveCurPos', getcurpos())
  prop_type_add('LspSymbolMatch', {bufnr: symPopupMenu->winbufnr(),
				   highlight: 'Title',
				   override: true})

  # Start with the symbol under the cursor
  var cmds =<< trim eval END
    [{curSymIdx + 1}, 1]->cursor()
    :normal! z.
  END
  win_execute(symPopupMenu, cmds, 'silent!')

  # Highlight the name and range of the first symbol
  SymbolHighlight(symbolTable, curSymIdx)
enddef

# process the 'textDocument/documentSymbol' reply from the LSP server
# Result: DocumentSymbol[] | SymbolInformation[] | null
# Display the symbols in a popup window and jump to the selected symbol
export def DocSymbolPopup(lspserver: dict<any>, docSymbol: any, fname: string)
  var symList: list<dict<any>> = []

  if docSymbol->empty()
    return
  endif

  var bnr = fname->bufnr()

  if docSymbol[0]->has_key('location')
    # SymbolInformation[]
    symList = GetSymbolsInfoTable(lspserver, bnr, docSymbol)
  else
    # DocumentSymbol[]
    GetSymbolsDocSymbol(lspserver, bnr, docSymbol, symList)
  endif

  :redraw!
  SymbolPopupMenu(symList)
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
