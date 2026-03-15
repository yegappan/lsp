vim9script

# Functions related to displaying hover symbol information.

import './util.vim'
import './options.vim' as opt
import './buffer.vim' as buf

# Window id of the currently open hover popup, or 0 when none is open.
var hoverPopupWin: number = 0

# Last hover result cached per language server.  The cache is invalidated when
# the buffer, cursor position or changedtick differs from the cached request.
var hoverCache: dict<dict<any>> = {}

# Keys supported for scrolling the hover popup window.
const hoverScrollKeys = [
  "\<C-E>", "\<C-D>", "\<C-F>", "\<PageDown>",
  "\<C-Y>", "\<C-U>", "\<C-B>", "\<PageUp>",
  "\<C-Home>", "\<C-End>"
]

# Return true if 'key' is one of the recognised hover popup scroll keys.
def IsHoverScrollKey(key: string): bool
  return hoverScrollKeys->index(key) != -1
enddef

# Wrap 'value' in a fenced markdown code block annotated with 'lang'.
def MarkdownCodeBlock(lang: string, value: string): list<string>
  return [$'``` {lang}'] + value->split("\n") + ['```']
enddef

# Close the hover popup window (if present)
def HoverPopupClose()
  if hoverPopupWin != 0 && popup_list()->index(hoverPopupWin) != -1
    hoverPopupWin->popup_close()
  endif
  hoverPopupWin = 0
enddef

# Callback invoked by Vim when the hover popup is closed (e.g. via mouse click
# or the Esc key).  Clears the tracked window id so a fresh popup can be
# opened afterwards.
def HoverPopupClosed(winid: number, result: any)
  if hoverPopupWin == winid
    hoverPopupWin = 0
  endif
enddef

# Timer callback fired after the auto-hover debounce delay.  Clears the
# buffer-local timer handle, then guards against two race conditions before
# sending the hover request: the user may have switched buffers, or left
# normal mode (e.g. started typing).
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

# Cancel the pending auto-hover timer for buffer 'bnr', if one exists.
# The buffer-local 'LspHoverTimer' variable is reset to -1 afterwards.
export def HoverAutoStop(bnr: number)
  var timerid = bnr->getbufvar('LspHoverTimer', -1)
  if timerid != -1
    timer_stop(timerid)
    setbufvar(bnr, 'LspHoverTimer', -1)
  endif
enddef

# Schedule a debounced auto-hover request for buffer 'bnr'.  Any previously
# pending timer is cancelled first so rapid cursor movement resets the delay.
# Does nothing when 'hoverOnCursorHold' is disabled or no hover-capable server
# is attached.  In test mode the callback is invoked synchronously so tests do
# not need to wait for real timers.
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

# Return true when 'reqctx' still matches the current editor state (buffer,
# cursor line/column, and changedtick).  Used to discard stale async replies
# that arrived after the user moved the cursor or edited the buffer.
def HoverRequestContextMatches(reqctx: dict<any>): bool
  return reqctx.bnr == bufnr()
      && reqctx.changedtick == reqctx.bnr->getbufvar('changedtick', -1)
      && reqctx.lnum == line('.')
      && reqctx.col == charcol('.')
enddef

# When no hover text is available, emit a warning.  When 'hoverFallback' is
# enabled and 'keywordprg' points to something other than ':LspHover', the
# built-in 'K' command is invoked as a fallback instead.
def HoverShowEmpty(isSilent: bool)
  if &keywordprg !=# ':LspHover' && !empty(&l:keywordprg) &&
                                                  opt.lspOptions.hoverFallback
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
enddef

# Open (or reuse) the named preview window, clear its previous content, write
# the new hover text, set the filetype for syntax highlighting, then return
# focus to the originating window.
def HoverShowInPreview(hoverText: list<any>, hoverKind: string, cmdmods: string)
  execute $':silent! {cmdmods} pedit LspHover'
  :wincmd P
  :setlocal buftype=nofile
  :setlocal bufhidden=delete
  bufnr()->deletebufline(1, '$')
  hoverText->append(0)
  [1, 1]->cursor()
  exe $'setlocal ft={hoverKind}'
  :wincmd p
enddef

# Close any existing hover popup, then open a new one at the cursor.  There is
# never more than one hover popup on screen at a time.
def HoverShowInPopup(hoverText: list<any>, hoverKind: string)
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
enddef

# Render 'hoverText' to the user.  Dispatches to HoverShowEmpty when there is
# nothing to show, HoverShowInPreview when 'hoverInPreview' is set, or
# HoverShowInPopup otherwise.
def ShowHover(lspserver: dict<any>, hoverText: list<any>, hoverKind: string,
              cmdmods: string): void
  if hoverText->empty()
    HoverShowEmpty(cmdmods =~ 'silent')
    return
  endif

  if opt.lspOptions.hoverInPreview
    HoverShowInPreview(hoverText, hoverKind, cmdmods)
  else
    HoverShowInPopup(hoverText, hoverKind)
  endif
enddef

# Snapshot the current editor state (server id, buffer, cursor line/column,
# and changedtick) into a context dict.  The context is recorded with async
# hover requests so that stale replies can be detected on arrival, and stored
# alongside cache entries so that invalidation is automatic.
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

# Try to show hover information from the cache for 'reqctx'.  Returns true
# and renders the result when a valid, up-to-date cache entry exists for the
# current buffer position.  Returns false when no entry exists or the cached
# entry no longer matches the current buffer / cursor / changedtick.
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

# Convert the raw 'hoverResult' from the LSP server into a [lines, filetype]
# pair ready for display.  Handles all three shapes defined by the LSP spec:
#   MarkupContent  – dict with a 'kind' field ("plaintext" or "markdown")
#   MarkedString   – dict with a 'value' field, or a plain string
#   MarkedString[] – list mixing strings and dicts
# Returns [[], ''] for an empty or unrecognised result.
def HoverTextFromMarkupContent(lspserver: dict<any>, contents: dict<any>): list<any>
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
enddef

# Parse deprecated MarkedString dict form: {language?: string, value: string}.
def HoverTextFromMarkedStringDict(contents: dict<any>): list<any>
  var lang = contents->get('language', '')
  if lang->empty()
    return [contents.value->split("\n"), 'lspgfm']
  endif
  return [MarkdownCodeBlock(lang, contents.value), 'lspgfm']
enddef

# Parse MarkedString[] and join entries with a visual separator.
def HoverTextFromMarkedStringList(lspserver: dict<any>, contents: list<any>): list<any>
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
      continue
    endif

    if e_type == v:t_dict && e->has_key('value')
      var lang = e->get('language', '')
      if lang->empty()
        hoverText->extend(e.value->split("\n"))
      else
        hoverText->extend(MarkdownCodeBlock(lang, e.value))
      endif
      continue
    endif

    lspserver.errorLog(
      $'{strftime("%m/%d/%y %T")}: Unsupported hover list item ({e})'
    )
  endfor

  return [hoverText, 'lspgfm']
enddef

def GetHoverText(lspserver: dict<any>, hoverResult: any): list<any>
  if hoverResult->empty()
    return [[], '']
  endif

  var contents = hoverResult.contents
  var contents_type: number = contents->type()

  # MarkupContent
  if contents_type == v:t_dict && contents->has_key('kind')
    return HoverTextFromMarkupContent(lspserver, contents)
  endif

  # MarkedString (dict form) – deprecated but still used by some servers.
  if contents_type == v:t_dict && contents->has_key('value')
    return HoverTextFromMarkedStringDict(contents)
  endif

  # MarkedString (plain string form) – deprecated but still used by some servers.
  if contents_type == v:t_string
    return [contents->split("\n"), 'lspgfm']
  endif

  # interface MarkedString[]
  if contents_type == v:t_list
    return HoverTextFromMarkedStringList(lspserver, contents)
  endif

  lspserver.errorLog(
    $'{strftime("%m/%d/%y %T")}: Unsupported hover reply ({hoverResult})'
  )
  return [[], '']
enddef

# Key filter for the hover popup window.  Scroll keys (see hoverScrollKeys)
# are forwarded to the popup as normal-mode commands.  Pressing Esc closes the
# popup.  All other keys are not consumed, allowing them to reach the editor
# in the normal way.
def HoverWinFilterKey(hoverWin: number, key: string): bool
  var keyHandled = false

  if IsHoverScrollKey(key)
    # Forward the key as a normal-mode command so the popup scrolls.
    win_execute(hoverWin, $'normal! {key}')
    keyHandled = true
  endif

  if key == "\<Esc>"
    hoverWin->popup_close()
    keyHandled = true
  endif

  return keyHandled
enddef

# Handle a 'textDocument/hover' reply from the LSP server.
# 'hoverResult' is the raw LSP Hover object (or null/empty on no result).
# When 'reqctx' is provided the reply is validated against the current editor
# state: if the cursor has moved or the buffer has changed since the request
# was sent the reply is silently discarded.  Otherwise the result is stored in
# the hover cache and rendered via ShowHover.
export def HoverReply(lspserver: dict<any>, hoverResult: any, cmdmods: string,
                      reqctx: dict<any> = {}): void
  if !reqctx->empty() && !HoverRequestContextMatches(reqctx)
    return
  endif

  var [hoverText, hoverKind] = GetHoverText(lspserver, hoverResult)

  if !reqctx->empty()
    var cacheKey = reqctx.serverid->string()
    hoverCache[cacheKey] = {
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

# vim: tabstop=8 shiftwidth=2 softtabstop=2 expandtab
