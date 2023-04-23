vim9script

# LSP completion related functions

import './util.vim'
import './buffer.vim' as buf
import './options.vim' as opt
import './textedit.vim'

# per-filetype omni-completion enabled/disabled table
var ftypeOmniCtrlMap: dict<bool> = {}

var defaultKinds: dict<string> = {
  'Text':           't',
  'Method':         'm',
  'Function':       'f',
  'Constructor':    'C',
  'Field':          'F',
  'Variable':       'v',
  'Class':          'c',
  'Interface':      'i',
  'Module':         'M',
  'Property':       'p',
  'Unit':           'u',
  'Value':          'V',
  'Enum':           'e',
  'Keyword':        'k',
  'Snippet':        'S',
  'Color':          'C',
  'File':           'f',
  'Reference':      'r',
  'Folder':         'F',
  'EnumMember':     'E',
  'Constant':       'd',
  'Struct':         's',
  'Event':          'E',
  'Operator':       'o',
  'TypeParameter':  'T',
  'Buffer':         'B',
}

# Returns true if omni-completion is enabled for filetype 'ftype'.
# Otherwise, returns false.
def LspOmniComplEnabled(ftype: string): bool
  return ftypeOmniCtrlMap->get(ftype, false)
enddef

# Enables or disables omni-completion for filetype 'fype'
export def OmniComplSet(ftype: string, enabled: bool)
  ftypeOmniCtrlMap->extend({[ftype]: enabled})
enddef

# Map LSP complete item kind to a character
def LspCompleteItemKindChar(kind: number): string
  var kindMap: list<string> = [
    '',
    'Text',
    'Method',
    'Function',
    'Constructor',
    'Field',
    'Variable',
    'Class',
    'Interface',
    'Module',
    'Property',
    'Unit',
    'Value',
    'Enum',
    'Keyword',
    'Snippet',
    'Color',
    'File',
    'Reference',
    'Folder',
    'EnumMember',
    'Constant',
    'Struct',
    'Event',
    'Operator',
    'TypeParameter',
    'Buffer'
  ]

  if kind > 26
    return ''
  endif

  var kindName = kindMap[kind]
  var kindValue = defaultKinds[kindName]

  if opt.lspOptions.customCompletionKinds && opt.lspOptions.completionKinds->has_key(kindName)
    kindValue = opt.lspOptions.completionKinds[kindName]
  endif

  return kindValue
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
  if valid =~ ':$'
    return valid[: -2]
  endif
  return valid
enddef

# Integration with the UltiSnips plugin
def CompletionUltiSnips(prefix: string, items: list<dict<any>>)
  call UltiSnips#SnippetsInCurrentScope(1)
  for key in matchfuzzy(g:current_ulti_dict_info->keys(), prefix)
    var item = g:current_ulti_dict_info[key]
    var parts = split(item.location, ':')
    var txt = readfile(parts[0])[str2nr(parts[1]) : str2nr(parts[1]) + 20]
    var restxt = item.description .. "\n\n"
    for line in txt
      if line == "" || line[0 : 6] == "snippet"
	break
      else
	restxt = restxt .. line .. "\n"
      endif
    endfor
    items->add({
      label: key,
      data: {
	entryNames: [key],
      },
      kind: 15,
      documentation: restxt,
    })
  endfor
enddef

# add completion from current buf
def CompletionFromBuffer(items: list<dict<any>>)
    var words = {}
    for line in getline(1, '$')
        for word in line->split('\W\+')
            if !words->has_key(word) && word->len() > 1
                words[word] = 1
                items->add({
                    label: word,
                    data: {
                        entryNames: [word],
                    },
                    kind: 26,
                    documentation: "",
                })
            endif
        endfor
    endfor
enddef

# process the 'textDocument/completion' reply from the LSP server
# Result: CompletionItem[] | CompletionList | null
export def CompletionReply(lspserver: dict<any>, cItems: any)
  if cItems->empty()
    if lspserver.omniCompletePending
      lspserver.completeItems = []
      lspserver.omniCompletePending = false
    endif
    return
  endif

  lspserver.completeItemsIsIncomplete = false

  var items: list<dict<any>>
  if cItems->type() == v:t_list
    items = cItems
  else
    items = cItems.items
    lspserver.completeItemsIsIncomplete = cItems->get('isIncomplete', false)
  endif

  # Get the keyword prefix before the current cursor column.
  var chcol = charcol('.')
  var starttext = chcol == 1 ? '' : getline('.')[ : chcol - 2]
  var [prefix, start_idx, end_idx] = starttext->matchstrpos('\k*$')
  if opt.lspOptions.completionMatcher == 'icase'
    prefix = prefix->tolower()
  endif

  var start_col = start_idx + 1

  if opt.lspOptions.ultisnipsSupport
    CompletionUltiSnips(prefix, items)
  endif

  if opt.lspOptions.useBufferCompletion
    CompletionFromBuffer(items)
  endif

  var completeItems: list<dict<any>> = []
  for item in items
    var d: dict<any> = {}

    # TODO: Add proper support for item.textEdit.newText and item.textEdit.range
    # Keep in mind that item.textEdit.range can start be way before the typed
    # keyword.
    if item->has_key('textEdit') && opt.lspOptions.completionMatcher != 'fuzzy'
      var start_charcol: number
      if prefix != ''
	start_charcol = charidx(starttext, start_idx) + 1
      else
	start_charcol = chcol
      endif
      var textEdit = item.textEdit
      var textEditStartCol = textEdit.range.start.character
      if textEditStartCol != start_charcol
	var offset = start_charcol - textEditStartCol - 1
	d.word = textEdit.newText[offset : ]
      else
	d.word = textEdit.newText
      endif
    elseif item->has_key('insertText')
      d.word = item.insertText
    else
      d.word = item.label
    endif

    if item->get('insertTextFormat', 1) == 2
      # snippet completion.  Needs a snippet plugin to expand the snippet.
      # Remove all the snippet placeholders
      d.word = MakeValidWord(d.word)
    elseif !lspserver.completeItemsIsIncomplete
      # Don't attempt to filter on the items, when "isIncomplete" is set

      # plain text completion
      if prefix != ''
	# If the completion item text doesn't start with the current (case
	# ignored) keyword prefix, skip it.
	var filterText: string = item->get('filterText', d.word)
	if opt.lspOptions.completionMatcher == 'icase'
	  if filterText->tolower()->stridx(prefix) != 0
	    continue
	  endif
	# If the completion item text doesn't fuzzy match with the current
	# keyword prefix, skip it.
	elseif opt.lspOptions.completionMatcher == 'fuzzy'
	  if matchfuzzy([filterText], prefix)->empty()
	    continue
	  endif
	# If the completion item text doesn't start with the current keyword
	# prefix, skip it.
	else
	  if filterText->stridx(prefix) != 0
	    continue
	  endif
	endif
      endif
    endif

    d.abbr = item.label
    d.dup = 1

    if opt.lspOptions.completionMatcher == 'icase'
      d.icase = 1
    endif

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

    # Score is used for sorting.
    d.score = item->get('sortText')
    if d.score->empty()
      d.score = item->get('label', '')
    endif

    d.user_data = item
    completeItems->add(d)
  endfor

  if opt.lspOptions.completionMatcher != 'fuzzy'
    # Lexographical sort (case-insensitive).
    completeItems->sort((a, b) =>
      a.score == b.score ? 0 : a.score >? b.score ? 1 : -1)
  endif

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
	&& getline('.')->matchstr($'\C{completeItems[0].word}\>') != ''
      # only one complete match. No need to show the completion popup
      return
    endif

    completeItems->complete(start_col)
  else
    lspserver.completeItems = completeItems
    lspserver.omniCompletePending = false
  endif
enddef

# process the completion documentation
def ShowCompletionDocumentation(cItem: any)
  if cItem->empty() || cItem->type() != v:t_dict
    return
  endif

  # check if completion item is still selected
  var cInfo = complete_info()
  if cInfo->empty()
      || !cInfo.pum_visible
      || cInfo.selected == -1
      || cInfo.items[cInfo.selected]->type() != v:t_dict
      || cInfo.items[cInfo.selected].user_data->type() != v:t_dict
      || cInfo.items[cInfo.selected].user_data.label != cItem.label
    return
  endif

  var infoText: list<string>
  var infoKind: string

  if cItem->has_key('detail') && !cItem.detail->empty()
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
	util.ErrMsg($'Unsupported documentation type ({cItem.documentation.kind})')
	return
      endif
    elseif cItem.documentation->type() == v:t_string
      infoText->extend(cItem.documentation->split("\n"))
    else
      util.ErrMsg($'Unsupported documentation ({cItem.documentation->string()})')
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
      || cInfo.items[cInfo.selected].user_data->type() != v:t_dict
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

# process the 'completionItem/resolve' reply from the LSP server
# Result: CompletionItem
export def CompletionResolveReply(lspserver: dict<any>, cItem: any)
  ShowCompletionDocumentation(cItem)
enddef

# omni complete handler
def g:LspOmniFunc(findstart: number, base: string): any
  var lspserver: dict<any> = buf.CurbufGetServerChecked('completion')
  if lspserver->empty()
    return -2
  endif

  if findstart
    # first send all the changes in the current buffer to the LSP server
    listener_flush()

    lspserver.omniCompletePending = true
    lspserver.completeItems = []
    # initiate a request to LSP server to get list of completions
    lspserver.getCompletion(1, '')

    # locate the start of the word
    var line = getline('.')
    var start = charcol('.') - 1
    var keyword: string = ''
    while start > 0 && line[start - 1] =~ '\k'
      keyword = line[start - 1] .. keyword
      start -= 1
    endwhile
    lspserver.omniCompleteKeyword = keyword
    return line->byteidx(start)
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

    if lspserver.omniCompletePending
      return v:none
    endif

    var res: list<dict<any>> = lspserver.completeItems

    var prefix = lspserver.omniCompleteKeyword

    # Don't attempt to filter on the items, when "isIncomplete" is set
    if prefix == '' || lspserver.completeItemsIsIncomplete
      return res
    endif

    if opt.lspOptions.completionMatcher == 'fuzzy'
      return res->matchfuzzy(prefix, { key: 'word' })
    endif

    if opt.lspOptions.completionMatcher == 'icase'
      return res->filter((i, v) => v.word->tolower()->stridx(prefix) == 0)
    endif

    return res->filter((i, v) => v.word->stridx(prefix) == 0)
  endif
enddef

# Insert mode completion handler. Used when 24x7 completion is enabled
# (default).
def LspComplete()
  var lspserver: dict<any> = buf.CurbufGetServer('completion')
  if lspserver->empty() || !lspserver.running || !lspserver.ready
    return
  endif

  var cur_col: number = charcol('.')
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
    var trigChars = lspserver.completionTriggerChars
    var trigidx = trigChars->index(line[cur_col - 2])
    if trigidx == -1
      return
    endif
    # completion triggered by one of the trigger characters
    triggerKind = 2
    triggerChar = trigChars[trigidx]
  endif

  # first send all the changes in the current buffer to the LSP server
  listener_flush()

  # initiate a request to LSP server to get list of completions
  lspserver.getCompletion(triggerKind, triggerChar)
enddef

# Lazy complete documentation handler
def LspResolve()
  var lspserver: dict<any> = buf.CurbufGetServerChecked('completion')
  if lspserver->empty()
    return
  endif

  var item = v:event.completed_item
  if item->has_key('user_data') && !item.user_data->empty()
      if !item.user_data->has_key('documentation')
	lspserver.resolveCompletion(item.user_data)
      else
	ShowCompletionDocumentation(item.user_data)
      endif
  endif
enddef

# If the completion popup documentation window displays 'markdown' content,
# then set the 'filetype' to 'lspgfm'.
def LspSetPopupFileType()
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
  var lspserver: dict<any> = buf.CurbufGetServerChecked('completion')
  if lspserver->empty()
    return
  endif

  if v:completed_item->type() != v:t_dict
    return
  endif

  var completionData: any = v:completed_item->get('user_data', '')
  if completionData->type() != v:t_dict
      || !completionData->has_key('additionalTextEdits')
      || !opt.lspOptions.completionTextEdit
    return
  endif

  var bnr: number = bufnr()
  textedit.ApplyTextEdits(bnr, completionData.additionalTextEdits)
enddef

# Initialize buffer-local completion options and autocmds
export def BufferInit(lspserver: dict<any>, bnr: number, ftype: string)
  if !lspserver.isCompletionProvider
    # no support for completion
    return
  endif

  # buffer-local autocmds for completion
  var acmds: list<dict<any>> = []

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
      :inoremap <expr> <buffer> <CR> pumvisible() ? "\<C-Y>\<CR>" : "\<CR>"
    endif

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
  else
    if LspOmniComplEnabled(ftype)
      setbufvar(bnr, '&omnifunc', 'g:LspOmniFunc')
    endif
  endif

  acmds->add({bufnr: bnr,
	      event: 'CompleteChanged',
	      group: 'LSPBufferAutocmds',
	      cmd: 'LspSetPopupFileType()'})

  # Execute LSP server initiated text edits after completion
  acmds->add({bufnr: bnr,
	      event: 'CompleteDone',
	      group: 'LSPBufferAutocmds',
	      cmd: 'LspCompleteDone()'})

  autocmd_add(acmds)
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
