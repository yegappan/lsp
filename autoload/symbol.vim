vim9script

# Functions for dealing with symbols.
#   - LSP symbol menu and for searching symbols across the workspace.
#   - show symbol references
#   - jump to a symbol definition, declaration, type definition or
#     implementation

var opt = {}
var util = {}

if has('patch-8.2.4019')
  import './lspoptions.vim' as opt_import
  import './util.vim' as util_import

  opt.lspOptions = opt_import.lspOptions
  util.PushCursorToTagStack = util_import.PushCursorToTagStack
  util.WarnMsg = util_import.WarnMsg
  util.LspUriToFile = util_import.LspUriToFile
  util.GetLineByteFromPos = util_import.GetLineByteFromPos
else
  import lspOptions from './lspoptions.vim'
  import {WarnMsg,
	LspUriToFile,
	GetLineByteFromPos,
	PushCursorToTagStack} from './util.vim'

  opt.lspOptions = lspOptions
  util.WarnMsg = WarnMsg
  util.LspUriToFile = LspUriToFile
  util.GetLineByteFromPos = GetLineByteFromPos
  util.PushCursorToTagStack = PushCursorToTagStack
endif

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
    echo 'Symbol: ' .. query
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
    var winList: list<number> = fname->bufnr()->win_findbuf()
    if winList->len() == 0
      # Not present in any window
      if &modified || &buftype != ''
	# the current buffer is modified or is not a normal buffer, then open
	# the file in a new window
	exe "split " .. symTbl[result - 1].file
      else
	exe "confirm edit " .. symTbl[result - 1].file
      endif
    else
      winList[0]->win_gotoid()
    endif
    setcursorcharpos(symTbl[result - 1].pos.line + 1,
			symTbl[result - 1].pos.character + 1)
  catch
    # ignore exceptions
  endtry
enddef

# display a list of symbols from the workspace
export def ShowSymbolMenu(lspserver: dict<any>, query: string)
  # Create the popup menu
  var lnum = &lines - &cmdheight - 2 - 10
  var popupAttr = {
      title: 'Workspace Symbol Search',
      wrap: 0,
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
      filter: function('s:filterSymbols', [lspserver]),
      callback: function('s:jumpToWorkspaceSymbol')
  }
  lspserver.workspaceSymbolPopup = popup_menu([], popupAttr)
  lspserver.workspaceSymbolQuery = query
  prop_type_add('lspworkspacesymbol',
			{bufnr: lspserver.workspaceSymbolPopup->winbufnr(),
			 highlight: 'Title'})
  echo 'Symbol: ' .. query
enddef

# Display or peek symbol references in a location list
export def ShowReferences(lspserver: dict<any>, refs: list<dict<any>>)
  if refs->empty()
    util.WarnMsg('Error: No references found')
    lspserver.peekSymbol = false
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
  if lspserver.peekSymbol
    silent! pedit
    wincmd P
  endif
  setloclist(0, [], ' ', {title: 'Symbol Reference', items: qflist})
  var mods: string = ''
  if lspserver.peekSymbol
    # When peeking the references, open the location list in a vertically
    # split window to the right and make the location list window 30% of the
    # source window width
    mods = 'belowright vert :' .. (winwidth(0) * 30) / 100
  endif
  exe mods .. 'lopen'
  if !opt.lspOptions.keepFocusInReferences
    save_winid->win_gotoid()
  endif
  lspserver.peekSymbol = false
enddef

# Jump to the definition, declaration or implementation of a symbol.
# Also, used to peek at the definition, declaration or implementation of a
# symbol.
export def GotoSymbol(lspserver: dict<any>, location: dict<any>, type: string)
  if location->empty()
    var msg: string
    if type ==# 'textDocument/declaration'
      msg = 'Error: declaration is not found'
    elseif type ==# 'textDocument/typeDefinition'
      msg = 'Error: type definition is not found'
    elseif type ==# 'textDocument/implementation'
      msg = 'Error: implementation is not found'
    else
      msg = 'Error: definition is not found'
    endif

    util.WarnMsg(msg)
    if !lspserver.peekSymbol
      # pop the tag stack
      var tagstack: dict<any> = gettagstack()
      if tagstack.length > 0
        settagstack(winnr(), {curidx: tagstack.length}, 't')
      endif
    endif
    lspserver.peekSymbol = false
    return
  endif

  var fname = util.LspUriToFile(location.uri)
  if lspserver.peekSymbol
    # open the definition/declaration in the preview window and highlight the
    # matching symbol
    exe 'pedit ' .. fname
    var cur_wid = win_getid()
    wincmd P
    var pvwbuf = bufnr()
    setcursorcharpos(location.range.start.line + 1,
			location.range.start.character + 1)
    silent! matchdelete(101)
    var pos: list<number> = []
    var start_col: number
    var end_col: number
    start_col = util.GetLineByteFromPos(pvwbuf, location.range.start) + 1
    end_col = util.GetLineByteFromPos(pvwbuf, location.range.end) + 1
    pos->add(location.range.start.line + 1)
    pos->extend([start_col, end_col - start_col])
    matchaddpos('Search', [pos], 10, 101)
    win_gotoid(cur_wid)
  else
    # jump to the file and line containing the symbol
    var wid = fname->bufwinid()
    if wid != -1
      wid->win_gotoid()
    else
      var bnr: number = fname->bufnr()
      if bnr != -1
        if &modified || &buftype != ''
          exe 'sbuffer ' .. bnr
        else
          exe 'buf ' .. bnr
        endif
      else
        if &modified || &buftype != ''
          # if the current buffer has unsaved changes, then open the file in a
          # new window
          exe 'split ' .. fname
        else
          exe 'edit  ' .. fname
        endif
      endif
    endif
    # Set the previous cursor location mark. Instead of using setpos(), m' is
    # used so that the current location is added to the jump list.
    normal m'
    setcursorcharpos(location.range.start.line + 1,
			location.range.start.character + 1)
  endif
  redraw!
  lspserver.peekSymbol = false
enddef

# vim: shiftwidth=2 softtabstop=2
