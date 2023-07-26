vim9script

# Markdown parser
# Refer to https://github.github.com/gfm/
# for the GitHub Flavored Markdown specification.

# TODO: different highlight for different heading level
# TODO: links
# TODO: pretty table


# Container blocks
var block_quote = '^ \{,3\}\zs> \='
var list_marker = '[-+*]\|[0-9]\{1,9}[.)]'
var list_item = $'^\%({list_marker}\)\ze\s*$\|^ \{{,3}}\zs\%({list_marker}\) \{{1,4}}\ze\S\|^ \{{,3}}\zs\%({list_marker}\) \{{5}}\ze\s*\S'
# pattern to match list items
export var list_pattern = $'^ *\%({list_marker}\) *'


# Leaf blocks
var blank_line = '^\s*$'
var thematic_break = '^ \{,3\}\([-_*]\)\%(\s*\1\)\{2,\}\s*$'
var code_fence = '^ \{,3\}\(`\{3,\}\|\~\{3,\}\)\s*\(\S*\)'
var code_indent = '^ \{4\}\zs\s*\S.*'
var paragraph = '^\s*\zs\S.\{-}\s*\ze$'

var atx_heading = '^ \{,3}\zs\(#\{1,6}\) \s*\(.\{-}\)\s*\ze\%( #\{1,}\s*\)\=$'
var setext_heading = '^ \{,3}\zs\%(=\{1,}\|-\{1,}\)\ze *$'
var setext_heading_level = {"=": 1, "-": 2}

var table_delimiter = '^|\=\zs *:\=-\{1,}:\= *\%(| *:\=-\{1,}:\= *\)*\ze|\=$'

var punctuation = "[!\"#$%&'()*+,-./:;<=>?@[\\\\\\\]^_`{|}~]"

# Setting text properties
highlight LspBold term=bold cterm=bold gui=bold
highlight LspItalic term=italic cterm=italic gui=italic
highlight LspStrikeThrough term=strikethrough cterm=strikethrough gui=strikethrough
prop_type_add('LspMarkdownBold', {highlight: 'LspBold'})
prop_type_add('LspMarkdownItalic', {highlight: 'LspItalic'})
prop_type_add('LspMarkdownStrikeThrough', {highlight: 'LspStrikeThrough'})
prop_type_add('LspMarkdownHeading', {highlight: 'Function'})
prop_type_add('LspMarkdownCode', {highlight: 'PreProc'})
prop_type_add('LspMarkdownCodeBlock', {highlight: 'PreProc'})
prop_type_add('LspMarkdownListMarker', {highlight: 'Special'})
prop_type_add('LspMarkdownTableHeader', {highlight: 'Label'})
prop_type_add('LspMarkdownTableMarker', {highlight: 'Special'})


def GetMarkerProp(marker: string, col: number, ...opt: list<any>): dict<any>
  if marker == 'list_item'
    return {
      type: 'LspMarkdownListMarker',
      col: col,
      length: opt[0]
    }
  elseif marker == 'code_block'
    return {
      type: 'LspMarkdownCodeBlock',
      col: col,
      end_lnum: opt[0],
      end_col: opt[1]
    }
  elseif marker == 'heading'
    return {
      type: 'LspMarkdownHeading',
      col: col,
      length: opt[0]
    }
  elseif marker == 'table_header'
    return {
      type: 'LspMarkdownTableHeader',
      col: col,
      length: opt[0]
    }
  elseif marker == 'table_sep'
    return {
      type: 'LspMarkdownTableMarker',
      col: col,
      length: opt[0]
    }
  elseif marker == 'code_span'
    return {
      type: 'LspMarkdownCode',
      col: col,
      length: opt[0]
    }
  elseif marker == 'emphasis'
    return {
      type: 'LspMarkdownItalic',
      col: col,
      length: opt[0]
    }
  elseif marker == 'strong'
    return {
      type: 'LspMarkdownBold',
      col: col,
      length: opt[0]
    }
  elseif marker == 'strikethrough'
    return {
      type: 'LspMarkdownStrikeThrough',
      col: col,
      length: opt[0]
    }
  endif
  return {}
enddef

def GetCodeSpans(text: string): list<dict<any>>
  var code_spans = []
  var pos = 0
  while pos < text->len()
    var backtick = text->matchstrpos('\\*`', pos)
    if backtick[1] < 0
      break
    endif
    if backtick[0]->len() % 2 == 0
      # escaped backtick
      pos = backtick[2]
      continue
    endif
    pos = backtick[2] - 1
    var code_span = text->matchstrpos('^\(`\+\)`\@!.\{-}`\@1<!\1`\@!', pos)
    if code_span[1] < 0
      break
    endif
    var code_text = text->matchstrpos('^\(`\+\)\%(\zs \+\ze\|\([ \n]\=\)\zs.\{-}\S.\{-}\ze\2\)`\@1<!\1`\@!', pos)
    code_spans->add({
	marker: '`',
	start: [code_span[1], code_text[1]],
	end: [code_text[2], code_span[2]]
      })
    pos = code_span[2]
  endwhile
  return code_spans
enddef

def Unescape(text: string, block_marker: string = ""): string
  if block_marker == '`'
    # line breaks do not occur inside code spans
    return text->substitute('\n', ' ', 'g')
  endif
  # use 2 spaces instead of \ for hard line break
  var result = text->substitute('\\\@<!\(\(\\\\\)*\)\\\n', '\1  \n', 'g')
  # change soft line breaks
  result = result->substitute(' \@<! \=\n', ' ', 'g')
  # change hard line breaks
  result = result->substitute(' \{2,}\n', '\n', 'g')
  return result->substitute($'\\\({punctuation}\)', '\1', 'g')
enddef

def GetNextInlineDelimiter(text: string, start_pos: number, end_pos: number): dict<any>
  var pos = start_pos
  while pos < text->len()
    # search the first delimiter char
    var delimiter = text->matchstrpos('\\*[_*~]', pos)
    if delimiter[1] < 0 || delimiter[1] > end_pos
      return {}
    endif
    if delimiter[0]->len() % 2 == 0
      # escaped delimiter char
      pos = delimiter[2]
      continue
    endif
    pos = delimiter[2] - 1
    var delimiter_run = text->matchstrpos(
	    $'{delimiter[0][-1]->substitute("\\([*~]\\)", "\\\\\\1", "g")}\+',
	    pos)
    if delimiter_run[0][0] == '~' && delimiter_run[0]->len() > 2
      pos = delimiter_run[2]
      continue
    endif
    var add_char = ''
    if pos > 0
      pos -= 1
      add_char = '.'
    endif
    var delim_regex = delimiter_run[0]->substitute('\([*~]\)', '\\\1', 'g')
    var is_left = text->match($'^{add_char}{delim_regex}\%(\s\|$\|{punctuation}\)\@!\|^{add_char}\%(\s\|^\|{punctuation}\)\@1<={delim_regex}{punctuation}', pos) >= 0
    var is_right = text->match($'^{add_char}\%(\s\|^\|{punctuation}\)\@1<!{delim_regex}\|^{add_char}{punctuation}\@1<={delim_regex}\%(\s\|$\|{punctuation}\)', pos) >= 0
    if !is_left && ! is_right
      pos = delimiter_run[2]
      continue
    endif
    if delimiter_run[0][0] == '_'
	&& text->match($'^\w{delimiter_run[0]}\w', pos) >= 0
      # intraword emphasis is disallowed
      pos = delimiter_run[2]
      continue
    endif
    return {
      marker: delimiter_run[0],
      start: [delimiter_run[1], delimiter_run[2]],
      left: is_left,
      right: is_right
    }
  endwhile
  return {}
enddef

def GetNextInlineBlock(text: string, blocks: list<any>, rel_pos: number): dict<any>
  var result = {
    text: '',
    props: []
  }
  var cur = blocks->remove(0)
  var pos = cur.start[1]
  while blocks->len() > 0 && cur.end[0] >= blocks[0].start[0]
    result.text ..= Unescape(text->strpart(pos, blocks[0].start[0] - pos), cur.marker[0])
    # get nested block
    var part = GetNextInlineBlock(text, blocks, rel_pos + result.text->len())
    result.text ..= part.text
    result.props += part.props
    pos = part.end_pos
  endwhile
  result.text ..= Unescape(text->strpart(pos, cur.end[0] - pos), cur.marker[0])
  # add props for current inline block
  var prop_type = {
    '`':  'code_span',
    '_':  'emphasis',
    '__': 'strong',
    '*':  'emphasis',
    '**': 'strong',
    '~':  'strikethrough',
    '~~': 'strikethrough'
  }
  result.props->insert(GetMarkerProp(prop_type[cur.marker],
				      rel_pos + 1,
				      result.text->len()))
  result->extend({'end_pos': cur.end[1]})
  return result
enddef

def ParseInlines(text: string, rel_pos: number = 0): dict<any>
  var formatted = {
    text: '',
    props: []
  }
  var code_spans = GetCodeSpans(text)

  var pos = 0
  var seq = []
  # search all emphasis
  while pos < text->len()
    var code_pos: list<number>
    if code_spans->len() > 0
      code_pos = [code_spans[0].start[0], code_spans[0].end[1]]
      if pos >= code_pos[0]
	pos = code_pos[1]
	seq->add(code_spans->remove(0))
	continue
      endif
    else
      code_pos = [text->len(), text->len()]
    endif
    var delimiter = GetNextInlineDelimiter(text, pos, code_pos[0])
    if delimiter->empty()
      pos = code_pos[1]
      continue
    endif
    if delimiter.right
      var idx = seq->len() - 1
      while idx >= 0
	if delimiter.marker[0] != seq[idx].marker[0]
	    || seq[idx]->has_key('end')
	  idx -= 1
	  continue
	endif
	if delimiter.left || seq[idx].right
	  # check the sum rule
	  if (delimiter.marker->len() + seq[idx].marker->len()) % 3 == 0
	      && (delimiter.marker->len() % 3 > 0
		  || seq[idx].marker->len() % 3 > 0)
	    # not valid condition
	    idx -= 1
	    continue
	  endif
	endif
	var marker_len = min([delimiter.marker->len(),
			      seq[idx].marker->len(), 2])
	if seq[idx].marker->len() > marker_len
	  var new_delim = {
	    marker: delimiter.marker[0]->repeat(marker_len),
	    start: [seq[idx].start[1] - marker_len, seq[idx].start[1]],
	    left: true,
	    right: false
	  }
	  seq[idx].marker = seq[idx].marker[: -1 - marker_len]
	  seq[idx].start[1] -= marker_len
	  seq[idx].right = false
	  idx += 1
	  seq->insert(new_delim, idx)
	endif
	seq[idx]->extend({
		    end: [delimiter.start[0],
			  delimiter.start[0] + marker_len]})
        # close all overlapped emphasis spans not closed
        for i in range(seq->len() - 1, idx + 1, -1)
          if !seq[i]->has_key('end')
            seq->remove(i)
          endif
        endfor
	if delimiter.marker->len() > marker_len
	  delimiter.start[0] += marker_len
	else
	  delimiter.left = false
	  break
	endif
	idx -= 1
      endwhile
    endif
    if delimiter.left
      seq->add(delimiter)
    endif
    pos = delimiter.start[1]
  endwhile
  while code_spans->len() > 0
    seq->add(code_spans->remove(0))
  endwhile
  # remove all not closed delimiters
  for i in range(seq->len() - 1, 0, -1)
    if !seq[i]->has_key('end')
      seq->remove(i)
    endif
  endfor

  # compose final text
  pos = 0
  while seq->len() > 0
    if pos < seq[0].start[0]
      formatted.text ..= Unescape(text->strpart(pos, seq[0].start[0] - pos))
      pos = seq[0].start[0]
    endif
    var inline = GetNextInlineBlock(text, seq,
				    rel_pos + formatted.text->len())
    formatted.text ..= inline.text
    formatted.props += inline.props
    pos = inline.end_pos
  endwhile
  if pos < text->len()
    formatted.text ..= Unescape(text->strpart(pos))
  endif
  return formatted
enddef

# new open container block
def CreateContainerBlock(match: list<any>, start_lnum: number): dict<any>
  if match[0][0] == '>'
    return {
      type: 'quote_block',
      lnum: start_lnum,
      indent: 0
    }
  else
    return {
      type: 'list_item',
      lnum: start_lnum,
      marker: $' {match[0]->matchstr("\\S\\+")} ',
      indent: match[2]
    }
  endif
enddef

# new open leaf block
def CreateLeafBlock(block_type: string, line: string, ...opt: list<any>): dict<any>
  if block_type == 'fenced_code'
    var token = line->matchlist(code_fence)
    return {
      type: block_type,
      fence: token[1],
      language: token[2],
      text: []
    }
  elseif block_type == 'indented_code'
    return {
      type: block_type,
      text: [line->matchstr(code_indent)]
    }
  elseif block_type == 'paragraph'
    return {
      type: block_type,
      text: [line->matchstr(paragraph)]
    }
  elseif block_type == 'heading'
    return {
      type: block_type,
      level: opt[0],
      text: line
    }
  elseif block_type == 'table'
    return {
      type: block_type,
      header: line,
      delimiter: opt[0],
      text: []
    }
  endif
  return {}
enddef

def NeedBlankLine(prev: string, cur: string): bool
  if prev == 'hr' || cur == 'hr'
    return false
  elseif prev == 'heading' || cur == 'heading'
    return true
  elseif prev == 'paragraph' && cur == 'paragraph'
    return true
  elseif prev != cur
    return true
  endif
  return false
enddef

def SplitLine(line: dict<any>, indent: number = 0): list<dict<any>>
  var lines: list<dict<any>> = []
  var tokens: list<string> = line.text->split("\n", true)
  if tokens->len() == 1
    lines->add(line)
    return lines
  endif
  var props: list<dict<any>> = line.props
  for cur_text in tokens
    var cur_props: list<dict<any>> = []
    var next_props: list<dict<any>> = []
    var length: number = cur_text->len()
    for prop in props
      if prop.col + prop.length - 1 <= length
        cur_props->add(prop)
      elseif prop.col > length
        prop.col -= length + 1
        next_props->add(prop)
      else
        var cur_length: number = length - prop.col + 1
        cur_props->add({
          type: prop.type,
          col: prop.col,
          length: cur_length
        })
        prop.col = 1
        prop.length -= cur_length + 1
        next_props->add(prop)
      endif
    endfor
    lines->add({
      text: cur_text,
      props: cur_props
    })
    props = next_props
  endfor
  return lines
enddef

var last_block: string = ''

def CloseBlocks(document: dict<list<any>>, blocks: list<dict<any>>, start: number = 0): void
  if start >= blocks->len()
    return
  endif
  var line: dict<any> = {
    text: '',
    props: []
  }
  if !document.content->empty() && NeedBlankLine(last_block, blocks[0].type)
    document.content->add({text: '', props: []})
  endif
  last_block = blocks[0].type

  for i in start->range()
    if blocks[i]->has_key('marker')
      if blocks[i].marker =~ '\S'
	line.props->add(GetMarkerProp('list_item',
				      line.text->len() + 1,
				      blocks[i].marker->len()))
	line.text ..= blocks[i].marker
	blocks[i].marker = ' '->repeat(blocks[i].marker->len())
      else
	line.text ..= blocks[i].marker
      endif
    endif
  endfor
  for block in blocks->remove(start, -1)
    if block.type =~ 'quote_block\|list_item'
      if block->has_key('marker')
	if block.marker =~ '\S'
	  line.props->add(GetMarkerProp('list_item',
					line.text->len() + 1,
					block.marker->len()))
	  line.text ..= block.marker
	  block.marker = ' '->repeat(block.marker->len())
	else
	  line.text ..= block.marker
	endif
      endif
    else
      # leaf block
      if block.type =~ '_code'
	if block.type == 'indented_code'
	  while !block.text->empty() && block.text[0] !~ '\S'
	    block.text->remove(0)
	  endwhile
	  while !block.text->empty() && block.text[-1] !~ '\S'
	    block.text->remove(-1)
	  endwhile
	endif
	if !block.text->empty()
	  var indent = ' '->repeat(line.text->len())
	  var max_len = mapnew(block.text, (_, l) => l->len())->max()
	  var text = block.text->remove(0)
	  line.text ..= text
	  document.content->add(line)
	  var startline = document.content->len()
	  for l in block.text
	    document.content->add({text: indent .. l})
	  endfor
	  if block->has_key('language')
	      && !globpath(&rtp, $'syntax/{block.language}.vim')->empty()
	    document.syntax->add({lang: block.language,
				  start: $'\%{startline}l\%{indent->len() + 1}c',
				  end: $'\%{document.content->len()}l$'})
	  else
	    line.props->add(GetMarkerProp('code_block',
					  indent->len() + 1,
					  document.content->len(),
					  indent->len() + max_len + 1))
	  endif
	endif
      elseif block.type == 'heading'
	line.props->add(GetMarkerProp('heading',
				      line.text->len() + 1,
				      block.text->len(),
				      block.level))
	var format = ParseInlines(block.text, line.text->len())
	line.text ..= format.text
	line.props += format.props
	document.content += SplitLine(line)
      elseif block.type == 'table'
	var indent = line.text
	var head = block.header->split('\\\@1<!|')
	var col1 = head->remove(0)
	var format = ParseInlines(col1, line.text->len())
	line.props->add(GetMarkerProp('table_header',
				      line.text->len() + 1,
				      format.text->len()))
	line.text ..= format.text
	line.props += format.props
	for colx in head
	  format = ParseInlines(colx, line.text->len() + 1)
	  line.props->add(GetMarkerProp('table_sep', line.text->len() + 1, 1))
	  line.props->add(GetMarkerProp('table_header',
					line.text->len() + 2,
					format.text->len()))
	  line.text ..= $'|{format.text}'
	  line.props += format.props
	endfor
	document.content->add(line)
	var data = {
	  text: indent .. block.delimiter,
	  props: [GetMarkerProp('table_sep',
				indent->len() + 1,
				block.delimiter->len())]
	}
	document.content->add(data)
	for row in block.text
	  data = {
	    text: indent,
	    props: []
	  }
	  var cell = row->split('\\\@1<!|')
	  col1 = cell->remove(0)
	  format = ParseInlines(col1, data.text->len())
	  data.text ..= format.text
	  data.props += format.props
	  for colx in cell
	    format = ParseInlines(colx, data.text->len() + 1)
	    data.props->add(GetMarkerProp('table_sep',
					  data.text->len() + 1,
					  1))
	    data.text ..= $'|{format.text}'
	    data.props += format.props
	  endfor
	  document.content->add(data)
	endfor
      elseif block.type == 'paragraph'
	var indent = line.text->len()
	var format = ParseInlines(block.text->join("\n")->substitute('\s\+$', '', ''), indent)
	line.text ..= format.text
	line.props += format.props
	document.content += SplitLine(line, indent)
      endif
    endif
  endfor
enddef

def ExpandTabs(line: string): string
  var block_marker = line->matchstrpos($'^ \{{,3}}>[ \t]\+\|^[ \t]*\%({list_marker}\)\=[ \t]*')
  if block_marker[0]->match('\t') < 0
    return line
  endif
  var begin: string = ""
  for char in block_marker[0]
    if char == '	'
      begin ..= ' '->repeat(4 - (begin->len() % 4))
    else
      begin ..= char
    endif
  endfor
  return begin .. line[block_marker[2] :]
enddef

export def ParseMarkdown(data: list<string>, width: number = 80): dict<list<any>>
  var document: dict<list<any>> = {content: [], syntax: []}
  var open_blocks: list<dict<any>> = []

  for l in data
    var line: string = ExpandTabs(l)
    var cur = 0

    # for each open block check if current line continue it
    while cur < open_blocks->len()
      if open_blocks[cur].type == 'quote_block'
	var marker = line->matchstrpos(block_quote)
	if marker[1] == -1
	  break
	endif
	line = line->strpart(marker[2])
      elseif open_blocks[cur].type == 'list_item'
	var marker = line->matchstrpos($'^ \{{{open_blocks[cur].indent}}}')
	if marker[1] == -1
	  break
	endif
	line = line->strpart(marker[2])
      elseif open_blocks[cur].type == 'fenced_code'
	if line =~ $'^ \{{,3}}{open_blocks[cur].fence}{open_blocks[cur].fence[0]}* *$'
	  CloseBlocks(document, open_blocks, cur)
	else
	  open_blocks[cur].text->add(line)
	endif
	cur = -1
	break
      elseif open_blocks[cur].type == 'indented_code'
	var marker = line->matchstrpos(code_indent)
	if marker[1] >= 0
	  open_blocks[cur].text->add(marker[0])
	  cur = -1
	endif
	break
      elseif open_blocks[cur].type == 'paragraph'
	if line =~ setext_heading
	  var marker = line->matchstrpos(setext_heading)
	  open_blocks->add(CreateLeafBlock(
				  'heading',
				  open_blocks->remove(cur).text->join("\n")->substitute('\s\+$', '', ''),
				  setext_heading_level[marker[0][0]]))
	  CloseBlocks(document, open_blocks, cur)
	  cur = -1
	elseif open_blocks[cur].text->len() == 1
	  # may be a table
	  var marker = line->matchstr(table_delimiter)
	  if !marker->empty()
	    if open_blocks[cur].text[0]->split('\\\@1<!|')->len() == marker->split('|')->len()
	      open_blocks->add(CreateLeafBlock(
				  'table',
				  open_blocks->remove(cur).text[0],
				  marker))
	      cur = -1
	    endif
	  endif
	endif
	break
      endif
      cur += 1
    endwhile

    if cur < 0
      # the whole line is already consumed
      continue
    endif

    # a thematic break close all previous blocks
    if line =~ thematic_break
      CloseBlocks(document, open_blocks)
      if &g:encoding == 'utf-8'
	document.content->add({text: "\u2500"->repeat(width)})
      else
	document.content->add({text: '-'->repeat(width)})
      endif
      last_block = 'hr'
      continue
    endif

    # check for new container blocks
    while true
      var block = line->matchstrpos($'{block_quote}\|{list_item}')
      if block[1] < 0
	break
      endif
      # close unmatched blocks
      CloseBlocks(document, open_blocks, cur)
      # start a new block
      open_blocks->add(CreateContainerBlock(block, document->len()))
      cur = open_blocks->len()
      line = line->strpart(block[2])
    endwhile

    # check for leaf block
    if line =~ code_fence
      CloseBlocks(document, open_blocks, cur)
      open_blocks->add(CreateLeafBlock('fenced_code', line))
    elseif line =~ blank_line
      if open_blocks->empty()
	continue
      endif
      if open_blocks[-1].type == 'paragraph'
	CloseBlocks(document, open_blocks, min([cur, open_blocks->len() - 1]))
      elseif open_blocks[-1].type == 'table'
	CloseBlocks(document, open_blocks, open_blocks->len() - 1)
      elseif open_blocks[-1].type =~ '_code'
	open_blocks[-1].text->add(line)
      endif
    elseif line =~ code_indent
      if open_blocks->empty()
	open_blocks->add(CreateLeafBlock('indented_code', line))
      elseif open_blocks[-1].type =~ '_code'
	open_blocks[-1].text->add(line->matchstr(code_indent))
      elseif open_blocks[-1].type == 'paragraph'
	open_blocks[-1].text->add(line->matchstr(paragraph))
      else
        CloseBlocks(document, open_blocks, cur)
	open_blocks->add(CreateLeafBlock('indented_code', line))
      endif
    elseif line =~ atx_heading
      CloseBlocks(document, open_blocks, cur)
      var token = line->matchlist(atx_heading)
      open_blocks->add(CreateLeafBlock('heading', token[2], token[1]->len()))
      CloseBlocks(document, open_blocks, cur)
    elseif !open_blocks->empty()
      if open_blocks[-1].type == 'table'
	open_blocks[-1].text->add(line)
      elseif open_blocks[-1].type == 'paragraph'
	open_blocks[-1].text->add(line->matchstr(paragraph))
      else
        CloseBlocks(document, open_blocks, cur)
        open_blocks->add(CreateLeafBlock('paragraph', line))
      endif
    else
      open_blocks->add(CreateLeafBlock('paragraph', line))
    endif
  endfor

  CloseBlocks(document, open_blocks)
  return document
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
