vim9script

# Functions related to displaying hover symbol information.

import './util.vim'
import './options.vim' as opt

# process the 'textDocument/hover' reply from the LSP server
# Result: Hover | null
export def HoverReply(lspserver: dict<any>, _: any, reply: dict<any>): void
  if !util.SanitizeReply('textDocument/hover', reply)
    return
  endif

  var hoverText: list<string>
  var hoverKind: string

  if reply.result.contents->type() == v:t_dict
    if reply.result.contents->has_key('kind')
      # MarkupContent
      if reply.result.contents.kind == 'plaintext'
        hoverText = reply.result.contents.value->split("\n")
        hoverKind = 'text'
      elseif reply.result.contents.kind == 'markdown'
        hoverText = reply.result.contents.value->split("\n")
        hoverKind = 'markdown'
      else
        util.ErrMsg($'Error: Unsupported hover contents type ({reply.result.contents.kind})')
        return
      endif
    elseif reply.result.contents->has_key('value')
      # MarkedString
      hoverText = reply.result.contents.value->split("\n")
    else
      util.ErrMsg($'Error: Unsupported hover contents ({reply.result.contents})')
      return
    endif
  elseif reply.result.contents->type() == v:t_list
    # interface MarkedString[]
    for e in reply.result.contents
      if e->type() == v:t_string
        hoverText->extend(e->split("\n"))
      else
        hoverText->extend(e.value->split("\n"))
      endif
    endfor
  elseif reply.result.contents->type() == v:t_string
    if reply.result.contents->empty()
      return
    endif
    hoverText->extend(reply.result.contents->split("\n"))
  else
    util.ErrMsg($'Error: Unsupported hover contents ({reply.result.contents})')
    return
  endif

  if opt.lspOptions.hoverInPreview
    silent! pedit LspHoverReply
    wincmd P
    setlocal buftype=nofile
    setlocal bufhidden=delete
    exe $'setlocal ft={hoverKind}'
    bufnr()->deletebufline(1, '$')
    append(0, hoverText)
    cursor(1, 1)
    wincmd p
  else
    hoverText->popup_atcursor({moved: 'word'})
  endif
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
