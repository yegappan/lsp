vim9script

import './buffer.vim' as buf
import './util.vim'
import './options.vim' as opt


export def Mark2Ft(mark: string): string
  # TODO: Later should convert any mismatch between vim/markdown lang-names
  return glob($"{$VIMRUNTIME}/syntax/{mark}.vim")
enddef

export def CompletePopup()
  if exists('#User#LspCompletePopup')
    doautocmd <nomodeline> User LspCompletePopup
    return
  endif

  var fname: string = @%
  if fname == ''
    fname = "[unnamed]"
  endif

  var lspserver: dict<any> = buf.CurbufGetServer()
  if lspserver->empty()
    util.ErrMsg('Error: LSP server for "' .. fname .. '" is not found')
  endif

  var win_id = popup_findinfo()
  var buf_id = winbufnr(win_id)
  if buf_id < 2 || win_id == 0
    # popup not ready yet
  else
    var doc: dict<any> = v:event.completed_item->get('user_data', {})->
          \ get('documentation', {})
    var kind: string = doc->get('kind', "")

    if !empty(doc)
      setbufvar(buf_id, "&number", "0")
      if kind == 'markdown' && opt.lspOptions.markdownHighlight
        if opt.lspOptions.markdownCompact
          setwinvar(win_id, "&conceallevel", 3)
          MarkdownSyntaxCompact(win_id, buf_id)
        else
          setbufvar(buf_id, "&filetype", "markdown")
        endif
      endif
      popup_show(win_id)
    endif
  endif
enddef

export def MarkdownFindMarks(doc: string): list<any>
  var marks = []
  try
    substitute(doc, '```\s*\zs\w\+\ze\s*', '\=!!len(add(marks, submatch(0))) ? submatch(0) : ""', 'gne')
  catch
    return []
  endtry
  return marks
enddef

# Conceals markdown codefences
def MarkdownSyntaxCompact(win_id: number, buf_id: number)
  win_execute(win_id, '
        \ :syntax clear
        \ |
        \ syntax sync clear')
  if exists('g:markdown_fenced_languages')
    var fenced_languages = g:markdown_fenced_languages
    unlet g:markdown_fenced_languages
    win_execute(win_id, ':runtime! syntax/markdown.vim')
    g:markdown_fenced_languages = fenced_languages
  else
    win_execute(win_id, ':runtime! syntax/markdown.vim')
  endif
  win_execute(win_id, '
        \ :unlet b:current_syntax
        \ |
        \ syntax clear markdownCodeBlock
        \ |
        \ syntax clear markdownCode
        \ |
        \ syntax clear markdownEscape
        \ |
        \ syntax region markdownCode
        \ matchgroup=Conceal start=/\%(``\)\@!`/
        \ matchgroup=Conceal end=/\%(``\)\@!`/
        \ containedin=TOP keepend concealends
        \ |
        \ syntax region markdownIdDeclaration
        \ matchgroup=Conceal start=/\%(``\)\@!`/ end=/\%(``\)\@!`/ 
        \ keepend concealends containedin=TOP')
  # containedin=TOP forces our region overriding runtime-markdown regions

  var marks = MarkdownFindMarks(getbufline(buf_id, 0, '$')->join())
  for l in marks
    if !empty(Mark2Ft(l))
      win_execute(win_id, $"
            \ :syntax include @{toupper(l)} syntax/{l}.vim
            \ |
            \ syntax region {toupper(l)} 
            \ matchgroup=Conceal start=/```\\s*{l}\\s*/
            \ matchgroup=Conceal end=/```$/
            \ contains=@{toupper(l)} containedin=TOP keepend concealends")
    endif
  endfor
  win_execute(win_id, ':set conceallevel=3')
enddef

# Join newlines at markdown codefences
export def MarkdownCompact(doc: string): string
  var compacted = doc
  try
    compacted = substitute(compacted, '```\s*\w\+\s*\zs\n', ' ', 'ge')
    compacted = substitute(compacted, '\s*\zs\n\s*\ze```\(\n\|$\)', '', 'ge')
    return compacted
  catch
    util.ErrMsg("Error: MarkdownCompact substitute failed")
    return doc
  endtry
enddef
