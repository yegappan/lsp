vim9script

# Functions related to displaying hover symbol information.

import './util.vim'
import './options.vim' as opt

# process the 'textDocument/hover' reply from the LSP server
# Result: Hover | null
export def HoverReply(lspserver: dict<any>, hoverResult: any): void
  if hoverResult->empty()
    return
  endif

  var hoverText: list<string>
  var hoverKind: string

  if hoverResult.contents->type() == v:t_dict
    if hoverResult.contents->has_key('kind')
      # MarkupContent
      if hoverResult.contents.kind == 'plaintext'
        hoverText = hoverResult.contents.value->split("\n")
        hoverKind = 'text'
      elseif hoverResult.contents.kind == 'markdown'
        hoverText = hoverResult.contents.value->split("\n")
        hoverKind = 'lspgfm'
      else
        util.ErrMsg($'Error: Unsupported hover contents type ({hoverResult.contents.kind})')
        return
      endif
    elseif hoverResult.contents->has_key('value')
      # MarkedString
      hoverText->extend([$'``` {hoverResult.contents.language}'])
      hoverText->extend(hoverResult.contents.value->split("\n"))
      hoverText->extend(['```'])
      hoverKind = 'lspgfm'
    else
      util.ErrMsg($'Error: Unsupported hover contents ({hoverResult.contents})')
      return
    endif
  elseif hoverResult.contents->type() == v:t_list
    # interface MarkedString[]
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
    hoverKind = 'lspgfm'
  elseif hoverResult.contents->type() == v:t_string
    if hoverResult.contents->empty()
      return
    endif
    hoverText->extend(hoverResult.contents->split("\n"))
  else
    util.ErrMsg($'Error: Unsupported hover contents ({hoverResult.contents})')
    return
  endif

  if opt.lspOptions.hoverInPreview
    silent! pedit LspHoverReply
    wincmd P
    :setlocal buftype=nofile
    :setlocal bufhidden=delete
    bufnr()->deletebufline(1, '$')
    hoverText->append(0)
    [1, 1]->cursor()
    exe $'setlocal ft={hoverKind}'
    wincmd p
  else
    var winid = hoverText->popup_atcursor({moved: 'word',
					   maxwidth: 80,
					   border: [0, 1, 0, 1],
					   borderchars: [' ']})
    win_execute(winid, $'setlocal ft={hoverKind}')
  endif
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
