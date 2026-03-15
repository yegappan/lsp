vim9script

# Functions related to displaying hover symbol information.

import './util.vim'
import './options.vim' as opt

# Hover popup window id
var hoverPopupWin: number = 0

def HoverPopupClose()
  if hoverPopupWin != 0 && popup_list()->index(hoverPopupWin) != -1
    hoverPopupWin->popup_close()
  endif
  hoverPopupWin = 0
enddef

def HoverPopupClosed(winid: number, result: any)
  if hoverPopupWin == winid
    hoverPopupWin = 0
  endif
enddef

# Util used to compute the hoverText from textDocument/hover reply
def GetHoverText(lspserver: dict<any>, hoverResult: any): list<any>
  if hoverResult->empty()
    return ['', '']
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
    return ['', '']
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
  return ['', '']
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
export def HoverReply(lspserver: dict<any>, hoverResult: any, cmdmods: string): void
  var [hoverText, hoverKind] = GetHoverText(lspserver, hoverResult)
  var isSilent = cmdmods =~ 'silent'

  # Nothing to show
  if hoverText->empty()
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
    var popupAttrs = opt.PopupConfigure('Hover', {
      moved: 'any',
      close: 'click',
      fixed: true,
      maxwidth: 80,
      filter: HoverWinFilterKey,
      callback: HoverPopupClosed,
      padding: [0, 1, 0, 1]
    })
    hoverPopupWin = hoverText->popup_atcursor(popupAttrs)
    win_execute(hoverPopupWin, $'setlocal ft={hoverKind}')
  endif
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
