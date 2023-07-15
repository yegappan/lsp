vim9script

# Snippet support

# Integration with the UltiSnips plugin
export def CompletionUltiSnips(prefix: string, items: list<dict<any>>)
  call UltiSnips#SnippetsInCurrentScope(1)
  for key in matchfuzzy(g:current_ulti_dict_info->keys(), prefix)
    var item = g:current_ulti_dict_info[key]
    var parts = split(item.location, ':')
    var txt = parts[0]->readfile()[parts[1]->str2nr() : parts[1]->str2nr() + 20]
    var restxt = item.description .. "\n\n"
    for line in txt
      if line->empty() || line[0 : 6] == "snippet"
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

# Integration with the vim-vsnip plugin
export def CompletionVsnip(items: list<dict<any>>)
  def Pattern(abbr: string): string
    var chars = escape(abbr, '\/?')->split('\zs')
    var chars_pattern = '\%(\V' .. chars->join('\m\|\V') .. '\m\)'
    var separator = chars[0] =~ '\a' ? '\<' : ''
    return $'{separator}\V{chars[0]}\m{chars_pattern}*$'
  enddef

  if charcol('.') == 1
    return
  endif
  var starttext = getline('.')->slice(0, charcol('.') - 1)
  for item in vsnip#get_complete_items(bufnr())
    var match = starttext->matchstrpos(Pattern(item.abbr))
    if match[0] != ''
      var user_data = item.user_data->json_decode()
      var documentation = []
      for line in vsnip#to_string(user_data.vsnip.snippet)->split("\n")
	documentation->add(line)
      endfor
      items->add({
	label: item.abbr,
	filterText: item.word,
	insertTextFormat: 2,
	textEdit: {
	  newText: user_data.vsnip.snippet->join("\n"),
	  range: {
	    start: {
	      line: line('.'),
	      character: match[1],
	    },
	    ['end']: {
	      line: line('.'),
	      character: match[2],
	    },
	  },
	},
	data: {
	  entryNames: [item.word],
	},
	kind: 15,
	documentation: {
	  kind: 'markdown',
	  value: documentation->join("\n"),
	},
      })
    endif
  endfor
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
