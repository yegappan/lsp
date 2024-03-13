vim9script

# LSP completion related functions

import './util.vim'
import './buffer.vim' as buf
import './options.vim' as opt
import './textedit.vim'
import './snippet.vim'
import './codeaction.vim'

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

# Returns true if omni-completion is enabled for filetype "ftype".
# Otherwise, returns false.
def LspOmniComplEnabled(ftype: string): bool
  return ftypeOmniCtrlMap->get(ftype, false)
enddef

# Enables or disables omni-completion for filetype "fype"
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

  var lspOpts = opt.lspOptions
  if lspOpts.customCompletionKinds &&
      lspOpts.completionKinds->has_key(kindName)
    kindValue = lspOpts.completionKinds[kindName]
  endif

  return kindValue
enddef

# Remove all the snippet placeholders from "str" and return the value.
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

# add completion from current buf
def CompletionFromBuffer(items: list<dict<any>>)
  var words = {}
  var start = reltime()
  var timeout = opt.lspOptions.bufferCompletionTimeout
  var linenr = 1
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
    # Check every 200 lines if timeout is exceeded
    if timeout > 0 && linenr % 200 == 0 &&
	start->reltime()->reltimefloat() * 1000 > timeout
      break
    endif
    linenr += 1
  endfor
enddef

# process the 'textDocument/completion' reply from the LSP server
# Result: CompletionItem[] | CompletionList | null
export def CompletionReply(lspserver: dict<any>, cItems: any)
  lspserver.completeItemsIsIncomplete = false
  if cItems->empty()
    if lspserver.omniCompletePending
      lspserver.completeItems = []
      lspserver.omniCompletePending = false
    endif
    return
  endif

  var items: list<dict<any>>
  if cItems->type() == v:t_list
    items = cItems
  else
    items = cItems.items
    lspserver.completeItemsIsIncomplete = cItems->get('isIncomplete', false)
  endif

  var lspOpts = opt.lspOptions

  # Get the keyword prefix before the current cursor column.
  var chcol = charcol('.')
  var starttext = chcol == 1 ? '' : getline('.')[ : chcol - 2]
  var [prefix, start_idx, end_idx] = starttext->matchstrpos('\k*$')
  if lspOpts.completionMatcherValue == opt.COMPLETIONMATCHER_ICASE
    prefix = prefix->tolower()
  endif

  var start_col = start_idx + 1

  if lspOpts.ultisnipsSupport
    snippet.CompletionUltiSnips(prefix, items)
  elseif lspOpts.vsnipSupport
    snippet.CompletionVsnip(items)
  endif

  if lspOpts.useBufferCompletion
    CompletionFromBuffer(items)
  endif

  var completeItems: list<dict<any>> = []
  var itemsUsed: list<string> = []
  for item in items
    var d: dict<any> = {}

    # TODO: Add proper support for item.textEdit.newText and
    # item.textEdit.range.  Keep in mind that item.textEdit.range can start
    # way before the typed keyword.
    if item->has_key('textEdit') &&
	lspOpts.completionMatcherValue != opt.COMPLETIONMATCHER_FUZZY
      var start_charcol: number
      if !prefix->empty()
	start_charcol = charidx(starttext, start_idx) + 1
      else
	start_charcol = chcol
      endif
      var textEdit = item.textEdit
      var textEditRange: dict<any> = {}
      if textEdit->has_key('range')
	textEditRange = textEdit.range
      elseif textEdit->has_key('insert')
	textEditRange = textEdit.insert
      endif
      var textEditStartCol =
		util.GetCharIdxWithoutCompChar(bufnr(), textEditRange.start)
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
    elseif !lspserver.completeItemsIsIncomplete || lspOpts.useBufferCompletion
      # Filter items only when "isIncomplete" is set (otherwise server would
      #   have done the filtering) or when buffer completion is enabled

      # plain text completion
      if !prefix->empty()
	# If the completion item text doesn't start with the current (case
	# ignored) keyword prefix, skip it.
	var filterText: string = item->get('filterText', d.word)
	if lspOpts.completionMatcherValue == opt.COMPLETIONMATCHER_ICASE
	  if filterText->tolower()->stridx(prefix) != 0
	    continue
	  endif
	# If the completion item text doesn't fuzzy match with the current
	# keyword prefix, skip it.
	elseif lspOpts.completionMatcherValue == opt.COMPLETIONMATCHER_FUZZY
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

    if lspOpts.completionMatcherValue == opt.COMPLETIONMATCHER_ICASE
      d.icase = 1
    endif

    if item->has_key('kind') && item.kind != null
      # namespace CompletionItemKind
      # map LSP kind to complete-item-kind
      d.kind = LspCompleteItemKindChar(item.kind)
    endif

    if lspserver.completionLazyDoc
      d.info = 'Lazy doc'
    else
      if item->has_key('detail') && !item.detail->empty()
	# Solve a issue where if a server send a detail field
	# with a "\n", on the menu will be everything joined with
	# a "^@" separating it. (example: clangd)
	d.menu = item.detail->split("\n")[0]
      endif
      if item->has_key('documentation')
	var itemDoc = item.documentation
	if itemDoc->type() == v:t_string && !itemDoc->empty()
	  d.info = itemDoc
	elseif itemDoc->type() == v:t_dict
	    && itemDoc.value->type() == v:t_string
	  d.info = itemDoc.value
	endif
      endif
    endif

    # Score is used for sorting.
    d.score = item->get('sortText')
    if d.score->empty()
      d.score = item->get('label', '')
    endif

    # Dont include duplicate items
    if lspOpts.filterCompletionDuplicates       
      var key = d->get('word', '') ..
                d->get('info', '') ..
                d->get('kind', '') ..
                d->get('score', '') ..
                d->get('abbr', '') ..
                d->get('dup', '')
      if index(itemsUsed, key) != -1            
        continue                                                                          
      endif                                                                      
      add(itemsUsed, key)                       
    endif  

    d.user_data = item
    completeItems->add(d)
  endfor

  if lspOpts.completionMatcherValue != opt.COMPLETIONMATCHER_FUZZY
    # Lexographical sort (case-insensitive).
    completeItems->sort((a, b) =>
      a.score == b.score ? 0 : a.score >? b.score ? 1 : -1)
  endif

  if lspOpts.autoComplete && !lspserver.omniCompletePending
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

# Check if completion item is selected
def CheckCompletionItemSel(label: string): bool
  var cInfo = complete_info()
  if cInfo->empty() || !cInfo.pum_visible || cInfo.selected == -1
    return false
  endif
  var selItem = cInfo.items->get(cInfo.selected, {})
  if selItem->empty()
      || selItem->type() != v:t_dict
      || selItem.user_data->type() != v:t_dict
      || selItem.user_data.label != label
    return false
  endif
  return true
enddef

# Process the completion documentation
def ShowCompletionDocumentation(cItem: any)
  if cItem->empty() || cItem->type() != v:t_dict
    return
  endif

  # check if completion item is still selected
  if !CheckCompletionItemSel(cItem.label)
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
    var cItemDoc = cItem.documentation
    if cItemDoc->type() == v:t_dict
      # MarkupContent
      if cItemDoc.kind == 'plaintext'
	infoText->extend(cItemDoc.value->split("\n"))
	infoKind = 'text'
      elseif cItemDoc.kind == 'markdown'
	infoText->extend(cItemDoc.value->split("\n"))
	infoKind = 'lspgfm'
      else
	util.ErrMsg($'Unsupported documentation type ({cItemDoc.kind})')
	return
      endif
    elseif cItemDoc->type() == v:t_string
      infoText->extend(cItemDoc->split("\n"))
    else
      util.ErrMsg($'Unsupported documentation ({cItemDoc->string()})')
      return
    endif
  endif

  if infoText->empty()
    return
  endif

  # check if completion item is changed in meantime
  if !CheckCompletionItemSel(cItem.label)
    return
  endif

  # autoComplete or &omnifunc with &completeopt =~ 'popup'
  var id = popup_findinfo()
  if id > 0
    var bufnr = id->winbufnr()
    id->popup_settext(infoText)
    infoKind->setbufvar(bufnr, '&ft')
    id->popup_show()
  else
    # &omnifunc with &completeopt =~ 'preview'
    try
      :wincmd P
      :setlocal modifiable
      bufnr()->deletebufline(1, '$')
      infoText->append(0)
      [1, 1]->cursor()
      exe $'setlocal ft={infoKind}'
      :wincmd p
    catch /E441/ # No preview window
    endtry
  endif
enddef

# process the 'completionItem/resolve' reply from the LSP server
# Result: CompletionItem
export def CompletionResolveReply(lspserver: dict<any>, cItem: any)
  ShowCompletionDocumentation(cItem)
enddef

# Return trigger kind and trigger char. If completion trigger is not a keyword
# and not one of the triggerCharacters, return -1 for triggerKind.
def GetTriggerAttributes(lspserver: dict<any>): list<any>
  var triggerKind: number = 1
  var triggerChar: string = ''

  # Trigger kind is 1 for keyword and 2 for trigger char initiated completion.
  var line: string = getline('.')
  var cur_col = charcol('.')
  if line[cur_col - 2] !~ '\k'
    var trigChars = lspserver.completionTriggerChars
    var trigidx = trigChars->index(line[cur_col - 2])
    if trigidx == -1
      triggerKind = -1
    else
      triggerKind = 2
      triggerChar = trigChars[trigidx]
    endif
  endif
  return [triggerKind, triggerChar]
enddef


# omni complete handler
def g:LspOmniFunc(findstart: number, base: string): any
  var lspserver: dict<any> = buf.CurbufGetServerChecked('completion')
  if lspserver->empty()
    return -2
  endif

  if findstart

    var [triggerKind, triggerChar] = GetTriggerAttributes(lspserver)
    if triggerKind < 0
      # previous character is not a keyword character or a trigger character,
      # so cancel omni completion.
      return -2
    endif

    # first send all the changes in the current buffer to the LSP server
    listener_flush()

    lspserver.omniCompletePending = true
    lspserver.completeItems = []

    # initiate a request to LSP server to get list of completions
    lspserver.getCompletion(triggerKind, triggerChar)

    # locate the start of the word
    var line = getline('.')->strpart(0, col('.') - 1)
    var keyword = line->matchstr('\k\+$')
    lspserver.omniCompleteKeyword = keyword
    return line->len() - keyword->len()
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
    if prefix->empty() || lspserver.completeItemsIsIncomplete
      return res
    endif

    var lspOpts = opt.lspOptions
    if lspOpts.completionMatcherValue == opt.COMPLETIONMATCHER_FUZZY
      return res->matchfuzzy(prefix, { key: 'word' })
    endif

    if lspOpts.completionMatcherValue == opt.COMPLETIONMATCHER_ICASE
      return res->filter((i, v) =>
	v.word->tolower()->stridx(prefix->tolower()) == 0)
    endif

    return res->filter((i, v) => v.word->stridx(prefix) == 0)
  endif
enddef

# For plugins that implement async completion this function indicates if
# omnifunc is waiting for LSP response.
def g:LspOmniCompletePending(): bool
  var lspserver: dict<any> = buf.CurbufGetServerChecked('completion')
  return !lspserver->empty() && lspserver.omniCompletePending
enddef

# Insert mode completion handler. Used when 24x7 completion is enabled
# (default).
def LspComplete()
  var lspserver: dict<any> = buf.CurbufGetServer('completion')
  if lspserver->empty() || !lspserver.running || !lspserver.ready
    return
  endif

  var [triggerKind, triggerChar] = GetTriggerAttributes(lspserver)
  if triggerKind < 0
    return
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
      if item.user_data->type() == v:t_dict && !item.user_data->has_key('documentation')
	lspserver.resolveCompletion(item.user_data)
      else
	ShowCompletionDocumentation(item.user_data)
      endif
  endif
enddef

# If the completion popup documentation window displays "markdown" content,
# then set the 'filetype' to "lspgfm".
def LspSetPopupFileType()
  var item = v:event.completed_item
  var cItem = item->get('user_data', {})
  if cItem->empty()
    return
  endif

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
def LspCompleteDone(bnr: number)
  var lspserver: dict<any> = buf.BufLspServerGet(bnr, 'completion')
  if lspserver->empty()
    return
  endif

  if v:completed_item->type() != v:t_dict
    return
  endif

  var completionData: any = v:completed_item->get('user_data', '')
  if completionData->type() != v:t_dict
      || !opt.lspOptions.completionTextEdit
    return
  endif

  if !completionData->has_key('additionalTextEdits')
    # Some language servers (e.g. typescript) delay the computation of the
    # additional text edits.  So try to resolve the completion item now to get
    # the text edits.
    completionData = lspserver.resolveCompletion(completionData, true)
  endif
  if !completionData->get('additionalTextEdits', {})->empty()
    textedit.ApplyTextEdits(bnr, completionData.additionalTextEdits)
  endif

  if completionData->has_key('command')
    # Some language servers (e.g. haskell-language-server) want to apply
    # additional commands after completion.
    codeaction.DoCommand(lspserver, completionData.command)
  endif

enddef

# Initialize buffer-local completion options and autocmds
export def BufferInit(lspserver: dict<any>, bnr: number, ftype: string)
  if !lspserver.isCompletionProvider
    # no support for completion
    return
  endif

  if !opt.lspOptions.autoComplete && !LspOmniComplEnabled(ftype) && !opt.lspOptions.omniComplete
    # LSP auto/omni completion support is not enabled for this buffer
    return
  endif

  # buffer-local autocmds for completion
  var acmds: list<dict<any>> = []

  # set options for insert mode completion
  if opt.lspOptions.autoComplete
    if lspserver.completionLazyDoc
      setbufvar(bnr, '&completeopt', 'menuone,popuphidden,noinsert,noselect')
    else
      setbufvar(bnr, '&completeopt', 'menuone,popup,noinsert,noselect')
    endif
    setbufvar(bnr, '&completepopup',
	      'width:80,highlight:Pmenu,align:item,border:off')
    # <Enter> in insert mode stops completion and inserts a <Enter>
    if !opt.lspOptions.noNewlineInCompletion
      :inoremap <expr> <buffer> <CR> pumvisible() ? "\<C-Y>\<CR>" : "\<CR>"
    endif

    # Trigger 24x7 insert mode completion when text is changed
    acmds->add({bufnr: bnr,
		event: 'TextChangedI',
		group: 'LSPBufferAutocmds',
		cmd: 'LspComplete()'})
  endif

  if LspOmniComplEnabled(ftype)
    setbufvar(bnr, '&omnifunc', 'g:LspOmniFunc')
  endif

  if lspserver.completionLazyDoc
    # resolve additional documentation for a selected item
    acmds->add({bufnr: bnr,
                event: 'CompleteChanged',
                group: 'LSPBufferAutocmds',
                cmd: 'LspResolve()'})
  endif

  acmds->add({bufnr: bnr,
	      event: 'CompleteChanged',
	      group: 'LSPBufferAutocmds',
	      cmd: 'LspSetPopupFileType()'})

  # Execute LSP server initiated text edits after completion
  acmds->add({bufnr: bnr,
	      event: 'CompleteDone',
	      group: 'LSPBufferAutocmds',
	      cmd: $'LspCompleteDone({bnr})'})

  autocmd_add(acmds)
enddef

# Buffer "bnr" is loaded in a window.  If omni-completion is enabled for this
# buffer, then set the 'omnifunc' option.
export def BufferLoadedInWin(bnr: number)
  if !opt.lspOptions.autoComplete
      && LspOmniComplEnabled(bnr->getbufvar('&filetype'))
    setbufvar(bnr, '&omnifunc', 'g:LspOmniFunc')
  endif
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
