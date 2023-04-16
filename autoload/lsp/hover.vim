vim9script

# Functions related to displaying hover symbol information.

import './util.vim'
import './options.vim' as opt

# Util used to compute the hoverText from textDocument/hover reply
def GetHoverText(lspserver: dict<any>, hoverResult: any): list<any>
  if hoverResult->empty()
    return ['', '']
  endif

  # MarkupContent
  if hoverResult.contents->type() == v:t_dict
      && hoverResult.contents->has_key('kind')
    if hoverResult.contents.kind == 'plaintext'
      return [hoverResult.contents.value->split("\n"), 'text']
    endif

    if hoverResult.contents.kind == 'markdown'
      return [hoverResult.contents.value->split("\n"), 'lspgfm']
    endif

    lspserver.errorLog(
      $'{strftime("%m/%d/%y %T")}: Unsupported hover contents kind ({hoverResult.contents.kind})'
    )
    return ['', '']
  endif

  # MarkedString
  if hoverResult.contents->type() == v:t_dict
      && hoverResult.contents->has_key('value')
    return [
      [$'``` {hoverResult.contents.language}']
        + hoverResult.contents.value->split("\n")
        + ['```'],
      'lspgfm'
    ]
  endif

  # MarkedString
  if hoverResult.contents->type() == v:t_string
    return [hoverResult.contents->split("\n"), 'lspgfm']
  endif

  # interface MarkedString[]
  if hoverResult.contents->type() == v:t_list
    var hoverText: list<string> = []
    for e in hoverResult.contents
      if !hoverText->empty()
        hoverText->extend(['- - -'])
      endif

      if e->type() == v:t_string
        hoverText->extend(e->split("\n"))
      else
        hoverText->extend([$'``` {e.language}'])
        hoverText->extend(e.value->split("\n"))
        hoverText->extend(['```'])
      endif
    endfor

    return [hoverText, 'lspgfm']
  endif

  lspserver.errorLog(
    $'{strftime("%m/%d/%y %T")}: Unsupported hover reply ({hoverResult})'
  )
  return ['', '']
enddef

# process the 'textDocument/hover' reply from the LSP server
# Result: Hover | null
export def HoverReply(silent: bool, lspserver: dict<any>, hoverResult: any): void
  var [hoverText, hoverKind] = GetHoverText(lspserver, hoverResult)

  # Nothing to show
  if hoverText->empty()
    if !silent
      util.WarnMsg($'No hover messages found for current position')
    endif
    return
  endif

  if opt.lspOptions.hoverInPreview
    :silent! pedit LspHoverReply
    :wincmd P
    :setlocal buftype=nofile
    :setlocal bufhidden=delete
    bufnr()->deletebufline(1, '$')
    hoverText->append(0)
    [1, 1]->cursor()
    exe $'setlocal ft={hoverKind}'
    :wincmd p
  else
    popup_clear()
    var winid = hoverText->popup_atcursor({moved: 'word',
					   maxwidth: 80,
					   border: [0, 1, 0, 1],
					   borderchars: [' ']})
    win_execute(winid, $'setlocal ft={hoverKind}')
  endif
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
