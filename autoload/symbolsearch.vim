vim9script

# Functions for the LSP symbol menu and for searching symbols across the
# workspace.

var util = {}

if has('patch-8.2.4019')
  import './util.vim' as util_import
  util.PushCursorToTagStack = util_import.PushCursorToTagStack
else
  import {PushCursorToTagStack} from './util.vim'
  util.PushCursorToTagStack = PushCursorToTagStack
endif

# Handle keys pressed when the workspace symbol popup menu is displayed
def s:filterSymbols(lspserver: dict<any>, popupID: number, key: string): bool
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
def s:jumpToWorkspaceSymbol(popupID: number, result: number): void
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

# vim: shiftwidth=2 softtabstop=2
