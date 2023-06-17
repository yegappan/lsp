vim9script

# Functions for dealing with type hierarchy (super types/sub types)

import './util.vim'
import './symbol.vim'

# Parse the type hierarchy in "typeHier" and displays a tree of type names
# in the current buffer.  This function is called recursively to display the
# super/sub type hierarchy.
#
# Returns the line number where the next type name should be added.
def TypeTreeGenerate(isSuper: bool, typeHier: dict<any>, pfx_arg: string,
			typeTree: list<string>, typeUriMap: list<dict<any>>)

  var itemHasChildren = false
  if isSuper
    if typeHier->has_key('parents') && !typeHier.parents->empty()
      itemHasChildren = true
    endif
  else
    if typeHier->has_key('children') && !typeHier.children->empty()
      itemHasChildren = true
    endif
  endif

  var itemBranchPfx: string
  if itemHasChildren
    itemBranchPfx = '▾ '
  else
    itemBranchPfx = pfx_arg->empty() ? '' : '  '
  endif

  var typestr: string
  var kindstr = symbol.SymbolKindToName(typeHier.kind)
  if kindstr != ''
    typestr = $'{pfx_arg}{itemBranchPfx}{typeHier.name} ({kindstr[0]})'
  else
    typestr = $'{pfx_arg}{itemBranchPfx}{typeHier.name}'
  endif
  typeTree->add(typestr)
  typeUriMap->add(typeHier)

  # last item to process
  if !itemHasChildren
    return
  endif

  var items: list<dict<any>>
  items = isSuper ? typeHier.parents : typeHier.children

  for item in items
    TypeTreeGenerate(isSuper, item, $'{pfx_arg}| ', typeTree, typeUriMap)
  endfor
enddef

# Display a popup with the file containing a type and highlight the line and
# the type name.
def UpdateTypeHierFileInPopup(lspserver: dict<any>, typeUriMap: list<dict<any>>)
  if lspserver.typeHierPopup->winbufnr() == -1
    return
  endif

  lspserver.typeHierFilePopup->popup_close()

  var n = line('.', lspserver.typeHierPopup) - 1
  var fname: string = util.LspUriToFile(typeUriMap[n].uri)

  var bnr = fname->bufadd()
  if bnr == 0
    return
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
    line: 'cursor+1',
    col: 1
  }
  lspserver.typeHierFilePopup = popup_create(bnr, popupAttrs)
  var cmds =<< trim eval END
    [{typeUriMap[n].range.start.line + 1}, 1]->cursor()
    :normal! z.
  END
  win_execute(lspserver.typeHierFilePopup, cmds)

  lspserver.typeHierFilePopup->clearmatches()
  var start_col = util.GetLineByteFromPos(bnr,
					typeUriMap[n].selectionRange.start) + 1
  var end_col = util.GetLineByteFromPos(bnr, typeUriMap[n].selectionRange.end)
  var pos = [[typeUriMap[n].selectionRange.start.line + 1,
	     start_col, end_col - start_col + 1]]
  matchaddpos('Search', pos, 10, -1, {window: lspserver.typeHierFilePopup})
enddef

def TypeHierPopupFilter(lspserver: dict<any>, typeUriMap: list<dict<any>>,
			popupID: number, key: string): bool
  popupID->popup_filter_menu(key)
  if lspserver.typeHierPopup->winbufnr() == -1
    # popup is closed
    if lspserver.typeHierFilePopup->winbufnr() != -1
      lspserver.typeHierFilePopup->popup_close()
    endif
    lspserver.typeHierFilePopup = -1
    lspserver.typeHierPopup = -1
  else
    UpdateTypeHierFileInPopup(lspserver, typeUriMap)
  endif

  return true
enddef

def TypeHierPopupCallback(lspserver: dict<any>, typeUriMap: list<dict<any>>,
			  popupID: number, selIdx: number)
  if lspserver.typeHierFilePopup->winbufnr() != -1
    lspserver.typeHierFilePopup->popup_close()
  endif
  lspserver.typeHierFilePopup = -1
  lspserver.typeHierPopup = -1

  if selIdx <= 0
    # popup is canceled
    return
  endif

  # Save the current cursor location in the tag stack.
  util.PushCursorToTagStack()
  util.JumpToLspLocation(typeUriMap[selIdx - 1], '')
enddef

# Show the super or sub type hierarchy items "types" as a tree in a popup
# window
export def ShowTypeHierarchy(lspserver: dict<any>, isSuper: bool, types: dict<any>)

  if lspserver.typeHierPopup->winbufnr() != -1
    # If the type hierarchy popup window is already present, close it.
    lspserver.typeHierPopup->popup_close()
  endif

  var typeTree: list<string>
  var typeUriMap: list<dict<any>>

  # Generate a tree of the type hierarchy items
  TypeTreeGenerate(isSuper, types, '', typeTree, typeUriMap)

  # Display a popup window with the type hierarchy tree and a popup window for
  # the file.
  var popupAttrs = {
      title: $'{isSuper ? "Super" : "Sub"}Type Hierarchy',
      wrap: 0,
      pos: 'topleft',
      line: 'cursor+1',
      col: winwidth(0) - 34,
      minheight: 10,
      maxheight: 10,
      minwidth: 30,
      maxwidth: 30,
      mapping: false,
      fixed: true,
      filter: function(TypeHierPopupFilter, [lspserver, typeUriMap]),
      callback: function(TypeHierPopupCallback, [lspserver, typeUriMap])
    }
  lspserver.typeHierPopup = popup_menu(typeTree, popupAttrs)
  UpdateTypeHierFileInPopup(lspserver, typeUriMap)
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
