vim9script

# Markdown parser
# Refer to https://github.github.com/gfm/
# for the GitHub Flavored Markdown specification.

import './constants.vim' as c
import './inline.vim' as inline
import './render.vim' as render

var reference_defs: dict<string> = {}

# ============================================================================
# BLOCK STRUCTURE CREATION
# ============================================================================

# Create a new container block (quote or list item)
# match: [matched_text, start_pos, end_pos] from matchstrpos()
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
      # End position becomes indent level for continuation
      indent: match[2]
    }
  endif
enddef

# Create a new leaf block (code, paragraph, heading, table, etc.)
# opt: type-specific parameters (e.g., heading level, table delimiter)
def CreateLeafBlock(block_type: string, line: string, ...opt: list<any>): dict<any>
  if block_type == 'fenced_code'
    var token = line->matchlist(c.CODE_FENCE)
    return {
      type: block_type,
      fence: token[1],
      language: token[2],
      text: []
    }
  elseif block_type == 'indented_code'
    return {
      type: block_type,
      text: [line->matchstr(c.CODE_INDENT)]
    }
  elseif block_type == 'paragraph'
    return {
      type: block_type,
      text: [line->matchstr(c.PARAGRAPH)]
    }
  elseif block_type == 'html_block'
    return {
      type: block_type,
      tag: opt[0],
      text: [line]
    }
  elseif block_type == 'html_comment'
    return {
      type: block_type,
      text: [line]
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

# Close and render blocks from start index onwards
# Delegated to markdown/render.vim to keep parsing and rendering separated.
def CloseBlocks(document: dict<list<any>>, blocks: list<dict<any>>, start: number = 0): void
  render.CloseBlocks(document, blocks, start)
enddef

# ============================================================================
# BLOCK PARSING - LINE PROCESSING
# ============================================================================

# Expand tabs to spaces in block markers (preserves tab stops)
def ExpandTabs(line: string): string
  # Fast path: no tabs present
  if stridx(line, "\t") < 0
    return line
  endif

  # Slow path: expand tabs (only when tabs are present)
  var block_marker = line->matchstrpos($'^ \{{,3}}>[ \t]\+\|^[ \t]*\%({c.LIST_MARKER}\)\=[ \t]*')
  if block_marker[1] < 0 || stridx(block_marker[0], "\t") < 0
    return line
  endif

  # Expand tabs respecting 4-space tab stops
  var begin: string = ""
  var begin_len = 0
  for char in block_marker[0]
    if char == '	'
      # Next tab stop
      var spaces_needed = 4 - (begin_len % 4)
      begin ..= ' '->repeat(spaces_needed)
      begin_len += spaces_needed
    else
      begin ..= char
      begin_len += 1
    endif
  endfor

  return begin .. line[block_marker[2] :]
enddef

# Extract link reference definitions and filter them from content
# Optimization: Early scan to avoid rebuilding array when no refs present
def FilterLinkReferences(data: list<string>): list<string>
  # Quick check: if no reference definitions found, return original data
  var has_refs = false
  for line in data
    if line =~ c.LINK_REFERENCE_DEF
      has_refs = true
      break
    endif
  endfor

  if !has_refs
    return data
  endif

  var filtered_data: list<string> = []
  var idx = 0
  var data_len = data->len()

  while idx < data_len
    var line = data[idx]
    var ref = line->matchlist(c.LINK_REFERENCE_DEF)

    if ref->len() > 0
      # Store reference definition
      reference_defs[inline.NormalizeReferenceLabel(ref[1])] = ref[2]

      # Check if next line is continuation with title
      if idx + 1 < data_len && data[idx + 1] =~ c.LINK_REFERENCE_TITLE_CONT
	idx += 1
      endif

      idx += 1
      continue
    endif

    filtered_data->add(line)
    idx += 1
  endwhile

  return filtered_data
enddef

# Check if a line continues an existing container block
def ContinueContainerBlock(line_in: string, block: dict<any>): list<any>
  # Returns [continued, new_line]
  var line = line_in
  if block.type == 'quote_block'
    var marker = line->matchstrpos(c.BLOCK_QUOTE)
    if marker[1] < 0
      return [false, line]
    endif
    return [true, line->strpart(marker[2])]
  elseif block.type == 'list_item'
    # New list item at same/outer level should stop continuation
    var new_list_match = line->matchstrpos(c.list_item)
    if new_list_match[1] >= 0 && new_list_match[1] < block.indent
      return [false, line]
    endif
    var marker = line->matchstrpos($'^ \{{{block.indent}}}')
    if marker[1] < 0
      return [false, line]
    endif
    return [true, line->strpart(marker[2])]
  endif

  return [false, line]
enddef

# Handle paragraph continuation or conversion (setext heading, table)
def HandleParagraphContinuation(line: string, cur: number,
				open_blocks: list<dict<any>>, document: dict<list<any>>): list<any>
  # Returns [consumed, should_break]

  # Check for setext heading underline
  if line =~ c.SETEXT_HEADING
    var marker = line->matchstrpos(c.SETEXT_HEADING)
    var para_block = open_blocks->remove(cur)
    var heading_text = para_block.text->join("\n")->substitute('\s\+$', '', '')
    open_blocks->add(CreateLeafBlock('heading', heading_text, c.SETEXT_HEADING_LEVEL[marker[0][0]]))
    CloseBlocks(document, open_blocks, cur)
    return [true, false]
  endif

  # Check for table delimiter (only for single-line paragraphs)
  var para_text = open_blocks[cur].text
  if para_text->len() == 1
    var delimiter = line->matchstr(c.TABLE_DELIMITER)
    if !delimiter->empty()
      var header_line = para_text[0]
      var header_cols = header_line->split('\\\@1<!|')->len()
      var delimiter_cols = delimiter->split('|')->len()

      if header_cols == delimiter_cols
	open_blocks->add(CreateLeafBlock('table', header_line, delimiter))
	open_blocks->remove(cur)
	return [true, false]
      endif
    endif
  endif

  return [false, true]
enddef

# Handle terminal open blocks (fenced code, indented code, HTML)
# Terminal blocks consume lines until their closing condition is met
def HandleTerminalOpenBlock(line: string, cur: number,
			    open_blocks: list<dict<any>>, document: dict<list<any>>): list<any>
  # Returns [handled, consumed, should_break]
  var block = open_blocks[cur]

  if block.type == 'fenced_code'
    var fence_char = block.fence[0]->escape('\^$.*[]~')
    var fence_len = block.fence->len()
    var fence_pattern = fence_char->repeat(fence_len)

    if line =~ $'^ \{{,3}}{fence_pattern}{fence_char}* *$'
      # Closing fence found
      CloseBlocks(document, open_blocks, cur)
    else
      # Add line to code block
      block.text->add(line)
    endif
    return [true, true, false]

  elseif block.type == 'indented_code'
    var marker = line->matchstrpos(c.CODE_INDENT)
    if marker[1] >= 0
      block.text->add(marker[0])
      return [true, true, false]
    endif
    return [true, false, true]

  elseif block.type == 'html_block'
    block.text->add(line)
    if line =~ $'^ \{{,3}}</{block.tag}>\s*$'
      CloseBlocks(document, open_blocks, cur)
    endif
    return [true, true, false]

  elseif block.type == 'html_comment'
    block.text->add(line)
    if line =~ '^ \{,3}-->\s*$'
      CloseBlocks(document, open_blocks, cur)
    endif
    return [true, true, false]
  endif

  return [false, false, false]
enddef

def ProcessContainerOpenBlock(line: string, block: dict<any>): list<any>
  var continued = ContinueContainerBlock(line, block)
  if !continued[0]
    return [line, false]
  endif
  return [continued[1], true]
enddef

def ProcessLeafOpenBlock(line: string, cur: number,
		    open_blocks: list<dict<any>>, document: dict<list<any>>): list<any>
  # Returns [handled, consumed, should_break]
  var block = open_blocks[cur]
  var terminal = HandleTerminalOpenBlock(line, cur, open_blocks, document)
  if terminal[0]
    return [true, terminal[1], terminal[2]]
  endif

  if c.IsParagraphBlock(block)
    var para_result = HandleParagraphContinuation(line, cur, open_blocks, document)
    return [true, para_result[0], para_result[1]]
  endif

  return [false, false, false]
enddef

# Process open blocks to see how many the current line continues
# Returns: [processed_line, block_index, consumed]
#   block_index: how many blocks matched (-1 if line was consumed)
#   consumed: true if line was fully processed (e.g., inside code block)
def ProcessOpenBlocks(line_in: string, open_blocks: list<dict<any>>, document: dict<list<any>>): list<any>
  var line = line_in
  var cur = 0

  while cur < open_blocks->len()
    var block = open_blocks[cur]

    if c.IsContainerBlock(block)
      # Handle container blocks
      var container_result = ProcessContainerOpenBlock(line, block)
      if !container_result[1]
	break
      endif
      line = container_result[0]

    else
      # Handle leaf blocks
      var leaf_result = ProcessLeafOpenBlock(line, cur, open_blocks, document)
      if leaf_result[0]
	if leaf_result[1]
	  return [line, -1, true]
	endif
	if leaf_result[2]
	  break
	endif
      endif
    endif

    cur += 1
  endwhile

  return [line, cur, false]
enddef

# Detect line type based on content patterns (dispatch optimization)
# Returns one of: 'code_fence', 'blank', 'code_indent', 'atx_heading',
# 'html_comment', 'html_block', 'new_containers', 'open_blocks', or 'default'
# Pattern matching happens once; handlers process based on type
def DetectLineType(line: string, new_containers_created: bool, open_blocks: list<dict<any>>): string
  if line =~ c.CODE_FENCE
    return 'code_fence'
  elseif line =~ c.BLANK_LINE
    return 'blank'
  elseif line =~ c.CODE_INDENT
    return 'code_indent'
  elseif line =~ c.ATX_HEADING
    return 'atx_heading'
  elseif line =~ c.HTML_COMMENT_OPEN
    return 'html_comment'
  elseif line =~ c.HTML_BLOCK_OPEN
    return 'html_block'
  elseif new_containers_created
    return 'new_containers'
  elseif !open_blocks->empty()
    return 'open_blocks'
  else
    return 'default'
  endif
enddef

# Handle fenced code block start
def HandleFencedCodeLine(line: string, cur: number, open_blocks: list<dict<any>>, document: dict<list<any>>): list<any>
  CloseBlocks(document, open_blocks, cur)
  open_blocks->add(CreateLeafBlock('fenced_code', line))
  return [line, cur]
enddef

# Handle blank line within document context
def HandleBlankLine(line: string, cur: number, open_blocks: list<dict<any>>, document: dict<list<any>>): list<any>
  if open_blocks->empty()
    return [line, cur]
  endif
  if c.IsParagraphBlock(open_blocks[-1])
    CloseBlocks(document, open_blocks, min([cur, open_blocks->len() - 1]))
  elseif c.IsTableBlock(open_blocks[-1])
    CloseBlocks(document, open_blocks, open_blocks->len() - 1)
  elseif c.IsCodeBlock(open_blocks[-1])
    open_blocks[-1].text->add(line)
  endif
  return [line, cur]
enddef

# Handle indented code block
def HandleIndentedCodeLine(line: string, cur: number, open_blocks: list<dict<any>>, document: dict<list<any>>): list<any>
  if open_blocks->empty()
    open_blocks->add(CreateLeafBlock('indented_code', line))
  elseif c.IsCodeBlock(open_blocks[-1])
    open_blocks[-1].text->add(line->matchstr(c.CODE_INDENT))
  elseif c.IsParagraphBlock(open_blocks[-1])
    open_blocks[-1].text->add(line->matchstr(c.PARAGRAPH))
  else
    CloseBlocks(document, open_blocks, cur)
    open_blocks->add(CreateLeafBlock('indented_code', line))
  endif
  return [line, cur]
enddef

# Handle ATX heading (# heading)
def HandleAtxHeadingLine(line: string, cur: number, open_blocks: list<dict<any>>, document: dict<list<any>>): list<any>
  CloseBlocks(document, open_blocks, cur)
  var token = line->matchlist(c.ATX_HEADING)
  var heading_text = token->len() > 2 ? token[2] : ''
  open_blocks->add(CreateLeafBlock('heading', heading_text, token[1]->len()))
  CloseBlocks(document, open_blocks, cur)
  return [line, cur]
enddef

# Handle HTML comment block
def HandleHtmlCommentLine(line: string, cur: number, open_blocks: list<dict<any>>, document: dict<list<any>>): list<any>
  CloseBlocks(document, open_blocks, cur)
  open_blocks->add(CreateLeafBlock('html_comment', line))
  if line =~ '^ \{,3}-->'
    CloseBlocks(document, open_blocks, cur)
  endif
  return [line, cur]
enddef

# Handle HTML block
def HandleHtmlBlockLine(line: string, cur: number, open_blocks: list<dict<any>>, document: dict<list<any>>): list<any>
  CloseBlocks(document, open_blocks, cur)
  var html_token = line->matchlist(c.HTML_BLOCK_OPEN)
  open_blocks->add(CreateLeafBlock('html_block', line, html_token[1]))
  if line =~ $'^ \{{,3}}</{html_token[1]}>\s*$'
    CloseBlocks(document, open_blocks, cur)
  endif
  return [line, cur]
enddef

# Handle text after new container blocks
def HandleNewContainersLine(line: string, cur: number, open_blocks: list<dict<any>>, document: dict<list<any>>): list<any>
  if line->len() > 0
    open_blocks->add(CreateLeafBlock('paragraph', line))
  endif
  return [line, cur]
enddef

def IsTopLevelListItemStart(line: string): bool
  var line_len = line->len()
  return line_len > 0 && line[0] != ' ' && line =~ '^\([-+*]\|[0-9]\+[.)]\) '
enddef

def HandleListItemOpenBlocksLine(line_in: string, cur_in: number,
			 open_blocks: list<dict<any>>, document: dict<list<any>>): list<any>
  var line = line_in
  var cur = cur_in

  # Check if line is a new list item at same/outer indentation level
  if IsTopLevelListItemStart(line)
    # Line starts with list marker at indent 0 - close current list item
    CloseBlocks(document, open_blocks, 0)
    # Process through HandleNewContainerBlocks
    var new_container = HandleNewContainerBlocks(line, open_blocks, document, 0)
    line = new_container[0]
    cur = new_container[1]
    if line->len() > 0
      open_blocks->add(CreateLeafBlock('paragraph', line))
    endif
  else
    # Continuation of current list item
    CloseBlocks(document, open_blocks, cur)
    open_blocks->add(CreateLeafBlock('paragraph', line))
  endif

  return [line, cur]
enddef

# Handle content within or after open blocks
def HandleOpenBlocksLine(line_in: string, cur_in: number, open_blocks: list<dict<any>>, document: dict<list<any>>): list<any>
  var line = line_in
  var cur = cur_in
  var last_block = open_blocks[-1]

  if c.IsTableBlock(last_block)
    last_block.text->add(line)
  elseif c.IsParagraphBlock(last_block)
    last_block.text->add(line->matchstr(c.PARAGRAPH))
  elseif last_block.type == 'list_item'
    var list_result = HandleListItemOpenBlocksLine(line, cur, open_blocks, document)
    line = list_result[0]
    cur = list_result[1]
  else
    CloseBlocks(document, open_blocks, cur)
    open_blocks->add(CreateLeafBlock('paragraph', line))
  endif
  return [line, cur]
enddef

# Handle default paragraph content
def HandleDefaultLine(line: string, cur: number, open_blocks: list<dict<any>>, document: dict<list<any>>): list<any>
  open_blocks->add(CreateLeafBlock('paragraph', line))
  return [line, cur]
enddef
def HandleThematicBreak(line: string, open_blocks: list<dict<any>>, document: dict<list<any>>, width: number): bool
  if line !~ c.THEMATIC_BREAK
    return false
  endif

  CloseBlocks(document, open_blocks)

  # Use Unicode box drawing character if available
  var hr_text: string
  if &g:encoding == 'utf-8'
    hr_text = "\u2500"->repeat(width)
  else
    hr_text = '-'->repeat(width)
  endif

  document.content->add({
    text: hr_text,
    props: [c.GetMarkerProp('thematic_break', 1, hr_text->len())]
  })
  render.SetLastBlock('hr')

  return true
enddef

# Detect and create new container blocks (quotes, lists)
def HandleNewContainerBlocks(line_in: string, open_blocks: list<dict<any>>, document: dict<list<any>>, cur: number): list<any>
  # Returns [remaining_line, new_cur]
  var line = line_in
  var new_cur = cur

  while true
    var block_match = line->matchstrpos($'{c.BLOCK_QUOTE}\|{c.list_item}')
    if block_match[1] < 0
      break
    endif

    # Close unmatched blocks before opening new container
    CloseBlocks(document, open_blocks, new_cur)

    # Start a new container block
    open_blocks->add(CreateContainerBlock(block_match, document->len()))
    new_cur = open_blocks->len()
    line = line->strpart(block_match[2])
  endwhile

  return [line, new_cur]
enddef

def HandleLineContent(line_in: string, cur_in: number, new_containers_created: bool,
	      open_blocks: list<dict<any>>, document: dict<list<any>>): list<any>
  # Returns [updated_line, updated_cur]
  var line = line_in
  var cur = cur_in

  # Detect line type and dispatch to appropriate handler
  var line_type = DetectLineType(line, new_containers_created, open_blocks)

  if line_type == 'code_fence'
    return HandleFencedCodeLine(line, cur, open_blocks, document)
  elseif line_type == 'blank'
    return HandleBlankLine(line, cur, open_blocks, document)
  elseif line_type == 'code_indent'
    return HandleIndentedCodeLine(line, cur, open_blocks, document)
  elseif line_type == 'atx_heading'
    return HandleAtxHeadingLine(line, cur, open_blocks, document)
  elseif line_type == 'html_comment'
    return HandleHtmlCommentLine(line, cur, open_blocks, document)
  elseif line_type == 'html_block'
    return HandleHtmlBlockLine(line, cur, open_blocks, document)
  elseif line_type == 'new_containers'
    return HandleNewContainersLine(line, cur, open_blocks, document)
  elseif line_type == 'open_blocks'
    return HandleOpenBlocksLine(line, cur, open_blocks, document)
  else
    return HandleDefaultLine(line, cur, open_blocks, document)
  endif
enddef

# ============================================================================
# MAIN MARKDOWN PARSER
# ============================================================================

# Parse markdown text into structured document with text properties
export def ParseMarkdown(data: list<string>, width: number = 80): dict<list<any>>
  var document: dict<list<any>> = {content: [], syntax: []}
  var open_blocks: list<dict<any>> = []
  reference_defs = {}
  inline.SetReferenceDefinitions(reference_defs)
  render.ResetRenderState()

  # Extract and filter link references
  var filtered_data: list<string> = FilterLinkReferences(data)

  for l in filtered_data
    var line: string = ExpandTabs(l)

    # Check if current line continues any open blocks
    var result = ProcessOpenBlocks(line, open_blocks, document)
    line = result[0]
    var cur = result[1]
    var consumed = result[2]

    if consumed
      # the whole line is already consumed
      continue
    endif

    # Handle thematic breaks
    if HandleThematicBreak(line, open_blocks, document, width)
      continue
    endif

    # Check for new container blocks
    var container_result = HandleNewContainerBlocks(line, open_blocks, document, cur)
    line = container_result[0]
    var new_containers_created = (container_result[1] > cur)
    cur = container_result[1]

    var line_result = HandleLineContent(line, cur, new_containers_created, open_blocks, document)
    line = line_result[0]
    cur = line_result[1]
  endfor

  CloseBlocks(document, open_blocks)

  return document
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
