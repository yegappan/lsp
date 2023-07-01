vim9script

# Functions related to handling LSP range selection.

import './util.vim'

# Visually (character-wise) select the text in a range
def SelectText(bnr: number, range: dict<dict<number>>)
  var rstart = range.start
  var rend = range.end
  var start_col: number = util.GetLineByteFromPos(bnr, rstart) + 1
  var end_col: number = util.GetLineByteFromPos(bnr, rend)

  :normal! v"_y
  setcharpos("'<", [0, rstart.line + 1, start_col, 0])
  setcharpos("'>", [0, rend.line + 1, end_col, 0])
  :normal! gv
enddef

# Process the range selection reply from LSP server and start a new selection
export def SelectionStart(lspserver: dict<any>, sel: list<dict<any>>)
  if sel->empty()
    return
  endif

  var bnr: number = bufnr()

  # save the reply for expanding or shrinking the selected text.
  lspserver.selection = {bnr: bnr, selRange: sel[0], index: 0}

  SelectText(bnr, sel[0].range)
enddef

# Locate the range in the LSP reply at a specified level
def GetSelRangeAtLevel(selRange: dict<any>, level: number): dict<any>
  var r: dict<any> = selRange
  var idx: number = 0

  while idx != level
    if !r->has_key('parent')
      break
    endif
    r = r.parent
    idx += 1
  endwhile

  return r
enddef

# Returns true if the current visual selection matches a range in the
# selection reply from LSP.
def SelectionFromLSP(range: dict<any>, startpos: list<number>, endpos: list<number>): bool
  var rstart = range.start
  var rend = range.end
  return startpos[1] == rstart.line + 1
			&& endpos[1] == rend.line + 1
			&& startpos[2] == rstart.character + 1
			&& endpos[2] == rend.character
enddef

# Expand or Shrink the current selection or start a new one.
export def SelectionModify(lspserver: dict<any>, expand: bool)
  var fname: string = @%
  var bnr: number = bufnr()

  if mode() == 'v' && !lspserver.selection->empty()
					&& lspserver.selection.bnr == bnr
					&& !lspserver.selection->empty()
    # Already in characterwise visual mode and the previous LSP selection
    # reply for this buffer is available. Modify the current selection.

    var selRange: dict<any> = lspserver.selection.selRange
    var startpos: list<number> = getcharpos('v')
    var endpos: list<number> = getcharpos('.')
    var idx: number = lspserver.selection.index

    # Locate the range in the LSP reply for the current selection
    selRange = GetSelRangeAtLevel(selRange, lspserver.selection.index)

    # If the current selection is present in the LSP reply, then modify the
    # selection
    if SelectionFromLSP(selRange.range, startpos, endpos)
      if expand
	# expand the selection
        if selRange->has_key('parent')
          selRange = selRange.parent
          lspserver.selection.index = idx + 1
        endif
      else
	# shrink the selection
	if idx > 0
	  idx -= 1
          selRange = GetSelRangeAtLevel(lspserver.selection.selRange, idx)
	  lspserver.selection.index = idx
	endif
      endif

      SelectText(bnr, selRange.range)
      return
    endif
  endif

  # Start a new selection
  lspserver.selectionRange(fname)
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
