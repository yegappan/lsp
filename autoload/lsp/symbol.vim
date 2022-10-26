vim9script

# Functions for dealing with symbols.
#   - LSP symbol menu and for searching symbols across the workspace.
#   - show symbol references
#   - jump to a symbol definition, declaration, type definition or
#     implementation

import './options.vim' as opt
import './util.vim'

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
    var winList: list<number> = fname->bufnr()->win_findbuf()
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
      winList[0]->win_gotoid()
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

# Display or peek symbol references in a location list
export def ShowReferences(lspserver: dict<any>, refs: list<dict<any>>, peekSymbol: bool)
  if refs->empty()
    util.WarnMsg('Error: No references found')
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
  if peekSymbol
    silent! pedit
    wincmd P
  endif
  setloclist(0, [], ' ', {title: 'Symbol Reference', items: qflist})
  var mods: string = ''
  if peekSymbol
    # When peeking the references, open the location list in a vertically
    # split window to the right and make the location list window 30% of the
    # source window width
    mods = $'belowright vert :{(winwidth(0) * 30) / 100}'
  endif
  exe $'{mods} lopen'
  if !opt.lspOptions.keepFocusInReferences
    save_winid->win_gotoid()
  endif
enddef

# Jump to the definition, declaration or implementation of a symbol.
# Also, used to peek at the definition, declaration or implementation of a
# symbol.
export def GotoSymbol(lspserver: dict<any>, location: dict<any>, peekSymbol: bool)
  var fname = util.LspUriToFile(location.uri)
  if peekSymbol
    # open the definition/declaration in the preview window and highlight the
    # matching symbol
    exe $'pedit {fname}'
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
	# Reuse an existing buffer. If the current buffer has unsaved changes
	# and 'hidden' is not set or if the current buffer is a special
	# buffer, then open the buffer in a new window.
        if (&modified && !&hidden) || &buftype != ''
          exe $'sbuffer {bnr}'
        else
          exe $'buf {bnr}'
        endif
      else
        if (&modified && !&hidden) || &buftype != ''
	  # if the current buffer has unsaved changes and 'hidden' is not set,
	  # or if the current buffer is a special buffer, then open the file
	  # in a new window
          exe $'split {fname}'
        else
          exe $'edit {fname}'
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

# vim: shiftwidth=2 softtabstop=2
