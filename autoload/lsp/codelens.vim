vim9script

import './codeaction.vim'

# Functions related to handling LSP code lens

export def ProcessCodeLens(lspserver: dict<any>, bnr: number, codeLensItems: list<dict<any>>)
  var text: list<string> = []
  for i in codeLensItems->len()->range()
    var item = codeLensItems[i]
    if !item->has_key('command')
      # resolve the code lens
      item = lspserver.resolveCodeLens(bnr, item)
      if item->empty()
	continue
      endif
      codeLensItems[i] = item
    endif
    text->add(printf("%d. %s\t| L%s:%s", i + 1, item.command.title,
			item.range.start.line + 1,
			getline(item.range.start.line + 1)))
  endfor

  var choice = inputlist(['Code Lens:'] + text)
  if choice < 1 || choice > codeLensItems->len()
    return
  endif

  codeaction.DoCommand(lspserver, codeLensItems[choice - 1].command)
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
