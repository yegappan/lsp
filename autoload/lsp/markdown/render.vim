vim9script

import './constants.vim' as c
import './inline.vim' as inline

# ============================================================================
# DOCUMENT RENDERING
# ============================================================================

var last_block: string = ''

export def ResetRenderState(): void
  last_block = ''
enddef

export def SetLastBlock(block_type: string): void
  last_block = block_type
enddef

# Determine if a blank line is needed between two block types
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

# Split a line with text properties at newline boundaries
def SplitLine(line: dict<any>): list<dict<any>>
  var tokens: list<string> = line.text->split("\n", true)
  var tokens_len = tokens->len()
  if tokens_len == 1
    return [line]
  endif

  var lines: list<dict<any>> = []
  var remaining_props: list<dict<any>> = line.props

  for cur_text in tokens
    var cur_props: list<dict<any>> = []
    var next_props: list<dict<any>> = []
    var text_length: number = cur_text->len()

    for prop in remaining_props
      var prop_end = prop.col + prop.length - 1

      if prop_end <= text_length
	# Property fits entirely in current line
	cur_props->add(prop)
      elseif prop.col > text_length
	# Property starts in next line
	prop.col -= text_length + 1
	next_props->add(prop)
      else
	# Property spans lines - split it
	var cur_length: number = text_length - prop.col + 1
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
    remaining_props = next_props
  endfor

  return lines
enddef

# Append indented lines to document
def AppendIndentedLines(document: dict<list<any>>, indent: string, lines: list<string>): void
  for line_text in lines
    document.content->add({text: indent .. line_text, props: []})
  endfor
enddef

def RenderRawMultilineBlock(block: dict<any>, line: dict<any>, document: dict<list<any>>): void
  var indent = ' '->repeat(line.text->len())
  var text = block.text->remove(0)
  line.text ..= text
  document.content->add(line)
  AppendIndentedLines(document, indent, block.text)
enddef

# Render code block with optional syntax highlighting
def RenderCodeBlock(block: dict<any>, line: dict<any>, document: dict<list<any>>): void
  var code_lines = block.text

  if block.type == 'indented_code'
    # Trim leading and trailing blank lines from indented code
    var first = 0
    var last = code_lines->len() - 1
    while first <= last && code_lines[first] !~ '\S'
      first += 1
    endwhile
    while last >= first && code_lines[last] !~ '\S'
      last -= 1
    endwhile

    if first > last
      return
    endif
    code_lines = code_lines[first : last]
  endif

  if code_lines->empty()
    return
  endif

  var content_list = document.content
  var line_text_len = line.text->len()
  var indent_str = ' '->repeat(line_text_len)

  var first_line = code_lines[0]
  line.text ..= first_line
  var remaining_lines = code_lines[1 :]

  var start_lnum = content_list->len() + 1

  # Find maximum line length for code block property
  var max_line_len = max(code_lines->mapnew((_, v) => v->len()))

  # Apply syntax highlighting if available, otherwise use code_block property
  var lang = block->get('language', '')
  if lang != '' && c.HasSyntaxForLanguage(lang)
    content_list->add(line)
    AppendIndentedLines(document, indent_str, remaining_lines)

    document.syntax->add({
      lang: lang,
      start: $'\%{start_lnum}l\%{line_text_len + 1}c',
      end: $'\%{content_list->len()}l$'
    })
  else
    var total_lines = code_lines->len()
    var final_lnum = start_lnum + total_lines - 1

    line.props->add(c.GetMarkerProp('code_block', line_text_len + 1, final_lnum, max_line_len + 1))
    content_list->add(line)
    AppendIndentedLines(document, indent_str, remaining_lines)
  endif
enddef

def RenderHTMLBlock(block: dict<any>, line: dict<any>, document: dict<list<any>>): void
  RenderRawMultilineBlock(block, line, document)
enddef

def RenderHTMLComment(block: dict<any>, line: dict<any>, document: dict<list<any>>): void
  RenderRawMultilineBlock(block, line, document)
enddef

def RenderHeading(block: dict<any>, line: dict<any>, document: dict<list<any>>): void
  var format = inline.ParseInlines(block.text, line.text->len())
  line.props->add(c.GetMarkerProp('heading',
		  line.text->len() + 1,
		  format.text->len(),
		  block.level))

  line.text ..= format.text
  line.props += format.props
  inline.AddTaskMarkerProp(line)
  document.content += SplitLine(line)
enddef

# Append table cells to line with proper formatting and properties
def AppendTableCells(line: dict<any>, cells: list<string>, is_header: bool): void
  var first_cell = cells->remove(0)->substitute('\\|', '|', 'g')
  var line_len = line.text->len()
  var format = inline.ParseInlines(first_cell, line_len)

  if is_header
    line.props->add(c.GetMarkerProp('table_header', line_len + 1, format.text->len()))
  endif

  line.text ..= format.text
  line.props += format.props

  for cell_text in cells
    var col_text = cell_text->substitute('\\|', '|', 'g')
    line_len = line.text->len()
    format = inline.ParseInlines(col_text, line_len + 1)

    line.props->add(c.GetMarkerProp('table_sep', line_len + 1, 1))
    if is_header
      line.props->add(c.GetMarkerProp('table_header', line_len + 2, format.text->len()))
    endif

    line.text ..= $'|{format.text}'
    line.props += format.props
  endfor
enddef

# Render table block with header, delimiter, and rows
def RenderTable(block: dict<any>, line: dict<any>, document: dict<list<any>>): void
  var indent = line.text
  var header_cells = block.header->split('\\\@1<!|')

  # Render header row
  AppendTableCells(line, header_cells, true)
  document.content->add(line)

  # Render delimiter row
  var delimiter_line = {
    text: indent .. block.delimiter,
    props: [c.GetMarkerProp('table_sep', indent->len() + 1, block.delimiter->len())]
  }
  document.content->add(delimiter_line)

  # Render data rows
  for row in block.text
    var data_line = {text: indent, props: []}
    var row_cells = row->split('\\\@1<!|')
    AppendTableCells(data_line, row_cells, false)
    document.content->add(data_line)
  endfor
enddef

def RenderParagraph(block: dict<any>, line: dict<any>, document: dict<list<any>>): void
  var format = inline.ParseInlines(block.text->join("\n")->substitute('\s\+$', '', ''), line.text->len())

  line.text ..= format.text
  line.props += format.props
  inline.AddTaskMarkerProp(line)
  document.content += SplitLine(line)
enddef

def RenderLeafBlock(block: dict<any>, line: dict<any>, document: dict<list<any>>): void
  if block.type =~ '_code'
    RenderCodeBlock(block, line, document)
  elseif block.type == 'html_block'
    RenderHTMLBlock(block, line, document)
  elseif block.type == 'html_comment'
    RenderHTMLComment(block, line, document)
  elseif block.type == 'heading'
    RenderHeading(block, line, document)
  elseif block.type == 'table'
    RenderTable(block, line, document)
  elseif block.type == 'paragraph'
    RenderParagraph(block, line, document)
  endif
enddef

def AppendContainerMarker(line: dict<any>, block: dict<any>): void
  var marker = block->get('marker', '')
  if marker == ''
    return
  endif

  var marker_len = marker->len()
  var current_text_len = line.text->len()

  if marker->trim() != ''
    line.props->add(c.GetMarkerProp('list_item',
				  current_text_len + 1,
				  marker_len))
    line.text ..= block.marker
    block.marker = ' '->repeat(marker_len)
  else
    line.text ..= block.marker
  endif
enddef

# Close and render blocks from start index onwards
export def CloseBlocks(document: dict<list<any>>, blocks: list<dict<any>>, start: number = 0): void
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

  # Process leading container markers for parent blocks (nested indentation)
  for i in range(start)
    AppendContainerMarker(line, blocks[i])
  endfor

  var prev_was_container = false
  for block in blocks->remove(start, -1)
    if block.type =~ 'quote_block\|list_item'
      # Finalize previous sibling container before adding new one
      if prev_was_container && line.text =~ '\S'
	document.content += SplitLine(line)
	line = {text: '', props: []}
      endif
      AppendContainerMarker(line, block)
      prev_was_container = true
    else
      # leaf block - dispatch to specialized render function
      RenderLeafBlock(block, line, document)
      prev_was_container = false
      # Reset line after leaf blocks since render functions handle
      # finalization
      line = {text: '', props: []}
    endif
  endfor
  # Finalize the last container block if it has content
  if line.text->len() > 0
    document.content += SplitLine(line)
  endif
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
