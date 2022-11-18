vim9script

# LSP completion related functions

import './util.vim'
import './buffer.vim' as buf
import './options.vim' as opt
import './textedit.vim'

# per-filetype omni-completion enabled/disabled table
var ftypeOmniCtrlMap: dict<bool> = {}

# Returns true if omni-completion is enabled for filetype 'ftype'.
# Otherwise, returns false.
def LspOmniComplEnabled(ftype: string): bool
  return ftypeOmniCtrlMap->get(ftype, v:false)
enddef

# Enables or disables omni-completion for filetype 'fype'
export def OmniComplSet(ftype: string, enabled: bool)
  ftypeOmniCtrlMap->extend({[ftype]: enabled})
enddef

# Map LSP complete item kind to a character
def LspCompleteItemKindChar(kind: number): string
  var kindMap: list<string> = ['',
		't', # Text
		'm', # Method
		'f', # Function
		'C', # Constructor
		'F', # Field
		'v', # Variable
		'c', # Class
		'i', # Interface
		'M', # Module
		'p', # Property
		'u', # Unit
		'V', # Value
		'e', # Enum
		'k', # Keyword
		'S', # Snippet
		'C', # Color
		'f', # File
		'r', # Reference
		'F', # Folder
		'E', # EnumMember
		'd', # Contant
		's', # Struct
		'E', # Event
		'o', # Operator
		'T'  # TypeParameter
	]
  if kind > 25
    return ''
  endif
  return kindMap[kind]
enddef

# Remove all the snippet placeholders from 'str' and return the value.
# Based on a similar function in the vim-lsp plugin.
def MakeValidWord(str_arg: string): string
  var str = str_arg->substitute('\$[0-9]\+\|\${\%(\\.\|[^}]\)\+}', '', 'g')
  str = str->substitute('\\\(.\)', '\1', 'g')
  var valid = str->matchstr('^[^"'' (<{\[\t\r\n]\+')
  if valid->empty()
    return str
  endif
  if valid =~# ':$'
    return valid[: -2]
  endif
  return valid
enddef

# process the 'textDocument/completion' reply from the LSP server
# Result: CompletionItem[] | CompletionList | null
export def CompletionReply(lspserver: dict<any>, cItems: any)
  if cItems->empty()
    return
  endif

  var items: list<dict<any>>
  if cItems->type() == v:t_list
    items = cItems
  else
    items = cItems.items
  endif

  var completeItems: list<dict<any>> = []
  for item in items
    var d: dict<any> = {}
    if item->has_key('textEdit') && item.textEdit->has_key('newText')
      d.word = item.textEdit.newText
    elseif item->has_key('insertText')
      d.word = item.insertText
    else
      d.word = item.label
    endif
    if item->get('insertTextFormat', 1) == 2
      # snippet completion.  Needs a snippet plugin to expand the snippet.
      # Remove all the snippet placeholders
      d.word = MakeValidWord(d.word)
    endif
    d.abbr = item.label
    d.dup = 1
    if item->has_key('kind')
      # namespace CompletionItemKind
      # map LSP kind to complete-item-kind
      d.kind = LspCompleteItemKindChar(item.kind)
    endif
    if lspserver.completionLazyDoc
      d.info = 'Lazy doc'
    else
      if item->has_key('detail') && item.detail != ''
        # Solve a issue where if a server send a detail field
        # with a "\n", on the menu will be everything joined with
        # a "^@" separating it. (example: clangd)
        d.menu = item.detail->split("\n")[0]
      endif
      if item->has_key('documentation')
        if item.documentation->type() == v:t_string && item.documentation != ''
          d.info = item.documentation
        elseif item.documentation->type() == v:t_dict
            && item.documentation.value->type() == v:t_string
          d.info = item.documentation.value
        endif
      endif
    endif
    d.user_data = item
    completeItems->add(d)
  endfor

  if opt.lspOptions.autoComplete && !lspserver.omniCompletePending
    if completeItems->empty()
      # no matches
      return
    endif

    var m = mode()
    if m != 'i' && m != 'R' && m != 'Rv'
      # If not in insert or replace mode, then don't start the completion
      return
    endif

    if completeItems->len() == 1
	&& getline('.')->matchstr(completeItems[0].word .. '\>') != ''
      # only one complete match. No need to show the completion popup
      return
    endif

    var start_col: number = 0

    # FIXME: The following doesn't work with typescript as one of the
    # completion item has a start column that is before the special character.
    # For example, when completing the methods for "str.", the dot is removed.
    #
    # # Find the start column for the completion.  If any of the entries
    # # returned by the LSP server has a starting position, then use that.
    # for item in items
    #   if item->has_key('textEdit')
    #     start_col = item.textEdit.range.start.character + 1
    #     break
    #   endif
    # endfor

    # LSP server didn't return a starting position for completion, search
    # backwards from the current cursor position for a non-keyword character.
    if start_col == 0
      var line: string = getline('.')
      var start = col('.') - 1
      while start > 0 && line[start - 1] =~ '\k'
	start -= 1
      endwhile
      start_col = start + 1
    endif

    completeItems->complete(start_col)
  else
    lspserver.completeItems = completeItems
    lspserver.omniCompletePending = false
  endif
enddef

# process the 'completionItem/resolve' reply from the LSP server
# Result: CompletionItem
export def CompletionResolveReply(lspserver: dict<any>, cItem: any)
  if cItem->empty() || cItem->type() != v:t_dict
    return
  endif

  # check if completion item is still selected
  var cInfo = complete_info()
  if cInfo->empty()
      || !cInfo.pum_visible
      || cInfo.selected == -1
      || cInfo.items[cInfo.selected]->type() != v:t_dict
      || cInfo.items[cInfo.selected].user_data.label != cItem.label
    return
  endif

  var infoText: list<string>
  var infoKind: string

  if cItem->has_key('detail')
    # Solve a issue where if a server send the detail field with "\n",
    # on the completion popup, everything will be joined with "^@"
    # (example: typescript-language-server)
    infoText->extend(cItem.detail->split("\n"))
  endif

  if cItem->has_key('documentation')
    if !infoText->empty()
      infoText->extend(['- - -'])
    endif
    if cItem.documentation->type() == v:t_dict
      # MarkupContent
      if cItem.documentation.kind == 'plaintext'
        infoText->extend(cItem.documentation.value->split("\n"))
        infoKind = 'text'
      elseif cItem.documentation.kind == 'markdown'
        infoText->extend(cItem.documentation.value->split("\n"))
        infoKind = 'lspgfm'
      else
        util.ErrMsg($'Error: Unsupported documentation type ({cItem.documentation.kind})')
        return
      endif
    elseif cItem.documentation->type() == v:t_string
      infoText->extend(cItem.documentation->split("\n"))
    else
      util.ErrMsg($'Error: Unsupported documentation ({cItem.documentation->string()})')
      return
    endif
  endif

  if infoText->empty()
    return
  endif

  # check if completion item is changed in meantime
  cInfo = complete_info()
  if cInfo->empty()
      || !cInfo.pum_visible
      || cInfo.selected == -1
      || cInfo.items[cInfo.selected]->type() != v:t_dict
      || cInfo.items[cInfo.selected].user_data.label != cItem.label
    return
  endif

  var id = popup_findinfo()
  if id > 0
    var bufnr = id->winbufnr()
    id->popup_settext(infoText)
    infoKind->setbufvar(bufnr, '&ft')
    id->popup_show()
  endif
enddef

# omni complete handler
def g:LspOmniFunc(findstart: number, base: string): any
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return -2
  endif

  if findstart
    # first send all the changes in the current buffer to the LSP server
    listener_flush()

    lspserver.omniCompletePending = v:true
    lspserver.completeItems = []
    # initiate a request to LSP server to get list of completions
    lspserver.getCompletion(1, '')

    # locate the start of the word
    var line = getline('.')
    var start = charcol('.') - 1
    while start > 0 && line[start - 1] =~ '\k'
      start -= 1
    endwhile
    return start
  else
    # Wait for the list of matches from the LSP server
    var count: number = 0
    while lspserver.omniCompletePending && count < 1000
      if complete_check()
	return v:none
      endif
      sleep 2m
      count += 1
    endwhile

    var res: list<dict<any>> = lspserver.completeItems
    return res->empty() ? v:none : res
  endif
enddef

# Insert mode completion handler. Used when 24x7 completion is enabled
# (default).
def LspComplete()
  var lspserver: dict<any> = buf.CurbufGetServer()
  if lspserver->empty() || !lspserver.running || !lspserver.ready
    return
  endif

  var cur_col: number = col('.')
  var line: string = getline('.')

  if cur_col == 0 || line->empty()
    return
  endif

  # Trigger kind is 1 for 24x7 code complete or manual invocation
  var triggerKind: number = 1
  var triggerChar: string = ''

  # If the character before the cursor is not a keyword character or is not
  # one of the LSP completion trigger characters, then do nothing.
  if line[cur_col - 2] !~ '\k'
    var trigidx = lspserver.completionTriggerChars->index(line[cur_col - 2])
    if trigidx == -1
      return
    endif
    # completion triggered by one of the trigger characters
    triggerKind = 2
    triggerChar = lspserver.completionTriggerChars[trigidx]
  endif

  # first send all the changes in the current buffer to the LSP server
  listener_flush()

  # initiate a request to LSP server to get list of completions
  lspserver.getCompletion(triggerKind, triggerChar)
enddef

# Lazy complete documentation handler
def LspResolve()
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  var item = v:event.completed_item
  if item->has_key('user_data') && !item.user_data->empty()
    lspserver.resolveCompletion(item.user_data)
  endif
enddef

# If the completion popup documentation window displays 'markdown' content,
# then set the 'filetype' to 'lspgfm'.
def LspSetFileType()
  var item = v:event.completed_item
  if !item->has_key('user_data') || item.user_data->empty()
    return
  endif

  var cItem = item.user_data
  if cItem->type() != v:t_dict || !cItem->has_key('documentation')
	\ || cItem.documentation->type() != v:t_dict
	\ || cItem.documentation.kind != 'markdown'
    return
  endif

  var id = popup_findinfo()
  if id > 0
    var bnum = id->winbufnr()
    setbufvar(bnum, '&ft', 'lspgfm')
  endif
enddef

# complete done handler (LSP server-initiated actions after completion)
def LspCompleteDone()
  var lspserver: dict<any> = buf.CurbufGetServerChecked()
  if lspserver->empty()
    return
  endif

  if v:completed_item->type() != v:t_dict
    return
  endif

  var completionData: any = v:completed_item->get('user_data', '')
  if completionData->type() != v:t_dict
      || !completionData->has_key('additionalTextEdits')
    return
  endif

  var bnr: number = bufnr()
  textedit.ApplyTextEdits(bnr, completionData.additionalTextEdits)
enddef

# Add buffer-local autocmds for completion
def AddAutocmds(lspserver: dict<any>, bnr: number)
  var acmds: list<dict<any>> = []

  # Insert-mode completion autocmds (if configured)
  if opt.lspOptions.autoComplete
    # Trigger 24x7 insert mode completion when text is changed
    acmds->add({bufnr: bnr,
		event: 'TextChangedI',
		group: 'LSPBufferAutocmds',
		cmd: 'LspComplete()'})
    if lspserver.completionLazyDoc
      # resolve additional documentation for a selected item
      acmds->add({bufnr: bnr,
		  event: 'CompleteChanged',
		  group: 'LSPBufferAutocmds',
		  cmd: 'LspResolve()'})
    endif
  endif

  acmds->add({bufnr: bnr,
                 event: 'CompleteChanged',
                 group: 'LSPBufferAutocmds',
                 cmd: 'LspSetFileType()'})

  # Execute LSP server initiated text edits after completion
  acmds->add({bufnr: bnr,
	      event: 'CompleteDone',
	      group: 'LSPBufferAutocmds',
	      cmd: 'LspCompleteDone()'})

  autocmd_add(acmds)
enddef

# Initialize buffer-local completion options and autocmds
export def BufferInit(lspserver: dict<any>, bnr: number, ftype: string)
  # set options for insert mode completion
  if opt.lspOptions.autoComplete
    if lspserver.completionLazyDoc
      setbufvar(bnr, '&completeopt', 'menuone,popuphidden,noinsert,noselect')
      setbufvar(bnr, '&completepopup', 'width:80,highlight:Pmenu,align:item,border:off')
    else
      setbufvar(bnr, '&completeopt', 'menuone,popup,noinsert,noselect')
      setbufvar(bnr, '&completepopup', 'border:off')
    endif
    # <Enter> in insert mode stops completion and inserts a <Enter>
    if !opt.lspOptions.noNewlineInCompletion
      inoremap <expr> <buffer> <CR> pumvisible() ? "\<C-Y>\<CR>" : "\<CR>"
    endif
  else
    if LspOmniComplEnabled(ftype)
      setbufvar(bnr, '&omnifunc', 'LspOmniFunc')
    endif
  endif

  AddAutocmds(lspserver, bnr)
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
