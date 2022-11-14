vim9script

import autoload 'lsp/markdown.vim' as md

var bnr: number = bufnr()
var popup_id: number
var document: dict<list<any>>

try
  popup_id = bnr->getbufinfo()[0].popups[0]
  document = md.ParseMarkdown(bnr->getbufline(1, '$'), winwidth(popup_id))
catch /.*/
  b:markdown_fallback = v:true
  finish
endtry

b:lsp_syntax = document.syntax
md.list_pattern->setbufvar(bnr, '&formatlistpat')
var settings = 'encoding=utf-8 linebreak breakindent breakindentopt=list:-1'
win_execute(popup_id, $'setlocal {settings}')
popup_id->popup_settext(document.content)

# vim: tabstop=8 shiftwidth=2 softtabstop=2
