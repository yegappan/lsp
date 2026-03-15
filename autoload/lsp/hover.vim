vim9script

# Functions related to displaying hover symbol information.

import './util.vim'
import './options.vim' as opt
import './buffer.vim' as buf

# Hover popup window id
var hoverPopupWin: number = 0

# Last hover result cached per language server.  The cache is invalidated when
# the buffer, cursor position or changedtick differs from the cached request.
var hoverCache: dict<dict<any>> = {}

# Close the hover popup window (if present)
def HoverPopupClose()
  if hoverPopupWin != 0 && popup_list()->index(hoverPopupWin) != -1
    hoverPopupWin->popup_close()
  endif
  hoverPopupWin = 0
enddef

# Hover popup window is closed.
def HoverPopupClosed(winid: number, result: any)
  if hoverPopupWin == winid
    hoverPopupWin = 0
  endif
enddef

# Timer callback to automatically display the hover information
def HoverAutoTimerCb(bnr: number, timerid: number)
  setbufvar(bnr, 'LspHoverTimer', -1)

  if bufnr() != bnr || mode() !=# 'n'
    return
  endif

  var lspserver: dict<any> = buf.BufLspServerGet(bnr, 'hover')
  if lspserver->empty()
    return
  endif

  lspserver.hover('silent')
enddef

# Stop the timer to automatically display the hover information
export def HoverAutoStop(bnr: number)
  var timerid = bnr->getbufvar('LspHoverTimer', -1)
  if timerid != -1
    timer_stop(timerid)
    setbufvar(bnr, 'LspHoverTimer', -1)
  endif
enddef

# Schedule the timer to automatically display the hover information
export def HoverAutoSchedule(bnr: number)
  if !opt.lspOptions.hoverOnCursorHold
    return
  endif

  HoverAutoStop(bnr)

  var lspserver: dict<any> = buf.BufLspServerGet(bnr, 'hover')
  if lspserver->empty()
    return
  endif

  var timerid: number
  if get(g:, 'LSPTest')
    HoverAutoTimerCb(bnr, -1)
  else
    timerid = timer_start(opt.lspOptions.hoverDelay,
			  function('HoverAutoTimerCb', [bnr]))
    setbufvar(bnr, 'LspHoverTimer', timerid)
  endif
enddef

# Hover context contains the buffer number, current cursor position and
# changedtick.  This is used to correctly match the cached hover information.
# Returns true if the cached context (reqctx) matches with the current hover
# context.
def HoverRequestContextMatches(reqctx: dict<any>): bool
  return reqctx.bnr == bufnr()
      && reqctx.changedtick == reqctx.bnr->getbufvar('changedtick', -1)
      && reqctx.lnum == line('.')
      && reqctx.col == charcol('.')
enddef

# Show the hover information in a popup or the preview window
def ShowHover(lspserver: dict<any>, hoverText: list<any>, hoverKind: string,
		cmdmods: string): void
  var isSilent = cmdmods =~ 'silent'

  # Nothing to show
  if hoverText->empty()
    # If 'keywordprg' is set to a value other than ':LspHover' and the
    # hoverFallback option is set, then invoke 'keywordprg'
    if &keywordprg !=# ':LspHover' && !empty(&l:keywordprg) && opt.lspOptions.hoverFallback
      if !isSilent
        util.WarnMsg($'No documentation found for current keyword; falling back to built-in.')
      endif
      try
        execute 'normal! K'
      catch /.*/
        # Ignore any errors from built-in fallback
      endtry
    else
      if !isSilent
        util.WarnMsg($'No documentation found for current keyword')
      endif
    endif
    return
  endif

  if opt.lspOptions.hoverInPreview
    execute $':silent! {cmdmods} pedit LspHover'
    :wincmd P
    :setlocal buftype=nofile
    :setlocal bufhidden=delete
    bufnr()->deletebufline(1, '$')
    hoverText->append(0)
    [1, 1]->cursor()
    exe $'setlocal ft={hoverKind}'
    :wincmd p
  else
    HoverPopupClose()
    var popupAttrs = {
      moved: 'any',
      close: 'click',
      fixed: true,
      maxwidth: 80,
      filter: HoverWinFilterKey,
      callback: HoverPopupClosed,
      padding: [0, 1, 0, 1]
    }
    popupAttrs = opt.PopupConfigure('Hover', popupAttrs)
    hoverPopupWin = hoverText->popup_atcursor(popupAttrs)
    win_execute(hoverPopupWin, $'setlocal ft={hoverKind}')
  endif
enddef

# Get the current context for showing the hover information
export def HoverRequestContextGet(lspserver: dict<any>): dict<any>
  var bnr = bufnr()
  return {
    serverid: lspserver.id,
    bnr: bnr,
    changedtick: bnr->getbufvar('changedtick', -1),
    lnum: line('.'),
    col: charcol('.')
  }
enddef

# Display the cached hover information
export def HoverShowCached(reqctx: dict<any>, lspserver: dict<any>,
		cmdmods: string): bool
  var cacheKey = reqctx.serverid->string()
  if !hoverCache->has_key(cacheKey)
    return false
  endif

  var entry = hoverCache[cacheKey]
  if entry.bnr != reqctx.bnr
      || entry.changedtick != reqctx.changedtick
      || entry.lnum != reqctx.lnum
      || entry.col != reqctx.col
    return false
  endif

  ShowHover(lspserver, entry.hoverText, entry.hoverKind, cmdmods)
  return true
enddef

# Util used to compute the hoverText from textDocument/hover reply
def GetHoverText(lspserver: dict<any>, hoverResult: any): list<any>
  if hoverResult->empty()
    return [[], '']
  endif

  var contents = hoverResult.contents
  var contents_type: number = contents->type()

  # MarkupContent
  if contents_type == v:t_dict
      && contents->has_key('kind')
    if contents.kind == 'plaintext'
      return [contents.value->split("\n"), 'text']
    endif

    if contents.kind == 'markdown'
      return [contents.value->split("\n"), 'lspgfm']
    endif

    lspserver.errorLog(
      $'{strftime("%m/%d/%y %T")}: Unsupported hover contents kind ({contents.kind})'
    )
    return [[], '']
  endif

  # MarkedString
  if contents_type == v:t_dict
      && contents->has_key('value')
    var lang = contents->get('language', '')
    if lang->empty()
      return [contents.value->split("\n"), 'lspgfm']
    endif
    return [
      [$'``` {lang}']
        + contents.value->split("\n")
        + ['```'],
      'lspgfm'
    ]
  endif

  # MarkedString
  if contents_type == v:t_string
    return [contents->split("\n"), 'lspgfm']
  endif

  # interface MarkedString[]
  if contents_type == v:t_list
    var hoverText: list<string> = []
    var first = true
    for e in contents
      if !first
        hoverText->add('- - -')
      endif
      first = false

      var e_type = e->type()

      if e_type == v:t_string
        hoverText->extend(e->split("\n"))
      elseif e_type == v:t_dict && e->has_key('value')
	var lang = e->get('language', '')
	if lang->empty()
	  hoverText->extend(e.value->split("\n"))
	else
	  hoverText->extend([$'``` {lang}'])
	  hoverText->extend(e.value->split("\n"))
	  hoverText->extend(['```'])
	endif
      else
	lspserver.errorLog(
	  $'{strftime("%m/%d/%y %T")}: Unsupported hover list item ({e})'
	)
      endif
    endfor

    return [hoverText, 'lspgfm']
  endif

  lspserver.errorLog(
    $'{strftime("%m/%d/%y %T")}: Unsupported hover reply ({hoverResult})'
  )
  return [[], '']
enddef

# Key filter function for the hover popup window.
# Only keys to scroll the popup window are supported.
def HoverWinFilterKey(hoverWin: number, key: string): bool
  var keyHandled = false

  if key == "\<C-E>"
      || key == "\<C-D>"
      || key == "\<C-F>"
      || key == "\<PageDown>"
      || key == "\<C-Y>"
      || key == "\<C-U>"
      || key == "\<C-B>"
      || key == "\<PageUp>"
      || key == "\<C-Home>"
      || key == "\<C-End>"
    # scroll the hover popup window
    win_execute(hoverWin, $'normal! {key}')
    keyHandled = true
  endif

  if key == "\<Esc>"
    hoverWin->popup_close()
    keyHandled = true
  endif

  return keyHandled
enddef

# process the 'textDocument/hover' reply from the LSP server
# Result: Hover | null
export def HoverReply(lspserver: dict<any>, hoverResult: any, cmdmods: string,
		reqctx: dict<any> = {}): void
  if !reqctx->empty() && !HoverRequestContextMatches(reqctx)
    return
  endif

  var [hoverText, hoverKind] = GetHoverText(lspserver, hoverResult)

  if !reqctx->empty()
    hoverCache[reqctx.serverid->string()] = {
      bnr: reqctx.bnr,
      changedtick: reqctx.changedtick,
      lnum: reqctx.lnum,
      col: reqctx.col,
      hoverText: hoverText,
      hoverKind: hoverKind
    }
  endif

  ShowHover(lspserver, hoverText, hoverKind, cmdmods)
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
