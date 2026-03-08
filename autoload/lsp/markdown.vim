vim9script

# Markdown parser
# Refer to https://github.github.com/gfm/
# for the GitHub Flavored Markdown specification.

import './markdown/block.vim' as block

# Public list pattern used by lspgfm ftplugin.
export var list_pattern = '^ *\([-+*]\|[0-9]\+[.)]\) '

# Parse markdown text into structured document with text properties.
# The parser implementation lives in markdown/block.vim.
export def ParseMarkdown(data: list<string>, width: number = 80): dict<list<any>>
  return block.ParseMarkdown(data, width)
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
