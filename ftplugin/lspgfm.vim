vim9script

import autoload 'lsp/markdown.vim' as md

# Update the preview window with the github flavored markdown text
def UpdatePreviewWindowContents(bnr: number, contentList: list<dict<any>>)
  :silent! bnr->deletebufline(1, '$')

  var lines: list<string> = []
  var props: dict<list<list<number>>>
  var lnum = 0

  # Each item in "contentList" is a Dict with the following items:
  #   text: text for this line
  #   props: list of text properties.  Each list item is a Dict.  See
  #   |popup-props| for more information.
  #
  # Need to convert the text properties from the format used by
  # popup_settext() to that used by prop_add_list().
  for entry in contentList
    lines->add(entry.text)
    lnum += 1
    if entry->has_key('props')
      for p in entry.props
	if !props->has_key(p.type)
	  props[p.type] = []
	endif
	if p->has_key('end_lnum')
	  props[p.type]->add([lnum, p.col, p.end_lnum, p.end_col])
	else
	  props[p.type]->add([lnum, p.col, lnum, p.col + p.length])
	endif
      endfor
    endif
  endfor
  setbufline(bnr, 1, lines)
  for prop_type in props->keys()
    prop_add_list({type: prop_type}, props[prop_type])
  endfor
enddef

# Render the github flavored markdown text.
# Text can be displayed either in a popup window or in a preview window.
def RenderGitHubMarkdownText()
  var bnr: number = bufnr()
  var winId: number = win_getid()
  var document: dict<list<any>>
  var inPreviewWindow = false

  if win_gettype() == 'preview'
    inPreviewWindow = true
  endif

  try
    if !inPreviewWindow
      winId = bnr->getbufinfo()[0].popups[0]
    endif
    # parse the github markdown content and convert it into a list of text and
    # list of associated text properties.
    document = md.ParseMarkdown(bnr->getbufline(1, '$'), winId->winwidth())
  catch /.*/
    b:markdown_fallback = v:true
    return
  endtry

  b:lsp_syntax = document.syntax
  md.list_pattern->setbufvar(bnr, '&formatlistpat')
  var settings = 'linebreak breakindent breakindentopt=list:-1'
  win_execute(winId, $'setlocal {settings}')
  if inPreviewWindow
    UpdatePreviewWindowContents(bnr, document.content)
  else
    winId->popup_settext(document.content)
  endif
enddef
RenderGitHubMarkdownText()

# vim: tabstop=8 shiftwidth=2 softtabstop=2
