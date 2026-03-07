vim9script

# Markdown parser
# Refer to https://github.github.com/gfm/
# for the GitHub Flavored Markdown specification.

# Configuration: Regex patterns for markdown parsing
const MARKDOWN_PATTERNS = {
  block_quote: '^ \{,3\}\zs> \=',
  list_marker: '[-+*]\|[0-9]\{1,9}[.)]',
  blank_line: '^\s*$',
  thematic_break: '^ \{,3\}\([-_*]\)\%(\s*\1\)\{2,\}\s*$',
  code_fence: '^ \{,3\}\(`\{3,\}\|\~\{3,\}\)\s*\([^`]*\)',
  code_indent: '^ \{4\}\zs\s*\S.*',
  paragraph: '^\s*\zs\S.\{-}\s*\ze$',
  html_block_open: '^ \{,3}<\([A-Za-z][A-Za-z0-9-]*\)\%([ \t][^>]*\)\?>\s*$',
  html_comment_open: '^ \{,3}<!--\s*$',
  atx_heading: '^ \{,3}\zs\(#\{1,6}\)\%( \s*\(.\{-}\)\s*\ze\%( #\{1,}\s*\)\=\)\=$',
  setext_heading: '^ \{,3}\zs\%(=\{1,}\|-\{1,}\)\ze *$',
  table_delimiter: '^|\=\zs *:\=-\{1,}:\= *\%(| *:\=-\{1,}:\= *\)*\ze|\=$',
  link_reference_def: '^ \{,3}\[\([^][]\+\)\]:\s*\(\S\+\)\%(.\{-}\)\=$',
  link_reference_title_cont: '^ \{1,3}\%(".*"\|(.*)\|''.*''\)\s*$',
  punctuation: "[!\"#$%&'()*+,-./:;<=>?@[\\\\\\\]^_`{|}~]"
}

# Expose shortcuts for frequently used patterns
const BLOCK_QUOTE = MARKDOWN_PATTERNS.block_quote
const LIST_MARKER = MARKDOWN_PATTERNS.list_marker
const BLANK_LINE = MARKDOWN_PATTERNS.blank_line
const THEMATIC_BREAK = MARKDOWN_PATTERNS.thematic_break
const CODE_FENCE = MARKDOWN_PATTERNS.code_fence
const CODE_INDENT = MARKDOWN_PATTERNS.code_indent
const PARAGRAPH = MARKDOWN_PATTERNS.paragraph
const HTML_BLOCK_OPEN = MARKDOWN_PATTERNS.html_block_open
const HTML_COMMENT_OPEN = MARKDOWN_PATTERNS.html_comment_open
const ATX_HEADING = MARKDOWN_PATTERNS.atx_heading
const SETEXT_HEADING = MARKDOWN_PATTERNS.setext_heading
const TABLE_DELIMITER = MARKDOWN_PATTERNS.table_delimiter
const LINK_REFERENCE_DEF = MARKDOWN_PATTERNS.link_reference_def
const LINK_REFERENCE_TITLE_CONT = MARKDOWN_PATTERNS.link_reference_title_cont
const PUNCTUATION = MARKDOWN_PATTERNS.punctuation

# Computed patterns
const SETEXT_HEADING_LEVEL = {'=': 1, '-': 2}
var list_item = '^\([-+*]\|[0-9]\+[.)]\)\ze\s*$\|^ \{,3}\zs\([-+*]\|[0-9]\+[.)]\) \{1,4}\ze\S\|^ \{,3}\zs\([-+*]\|[0-9]\+[.)]\) \{5}\ze\s*\S'
export var list_pattern = '^ *\([-+*]\|[0-9]\+[.)]\) '

# Map inline markers to property types
const INLINE_PROP_TYPES = {
  '`':  'code_span',
  '_':  'emphasis',
  '__': 'strong',
  '*':  'emphasis',
  '**': 'strong',
  '~':  'strikethrough',
  '~~': 'strikethrough'
}

# Configuration: Text property types and highlights
const PROP_TYPES = {
  bold: {type: 'LspMarkdownBold', highlight: 'LspBold'},
  italic: {type: 'LspMarkdownItalic', highlight: 'LspItalic'},
  strikethrough: {type: 'LspMarkdownStrikeThrough', highlight: 'LspStrikeThrough'},
  heading: {type: 'LspMarkdownHeading', highlight: 'Function'},
  code_span: {type: 'LspMarkdownCode', highlight: 'PreProc'},
  code_block: {type: 'LspMarkdownCodeBlock', highlight: 'PreProc'},
  list_item: {type: 'LspMarkdownListMarker', highlight: 'Special'},
  table_header: {type: 'LspMarkdownTableHeader', highlight: 'Label'},
  table_sep: {type: 'LspMarkdownTableMarker', highlight: 'Special'},
  link: {type: 'LspMarkdownLink', highlight: 'Underlined'},
  thematic_break: {type: 'LspMarkdownThematicBreak', highlight: 'Special'},
  task_marker: {type: 'LspMarkdownTaskMarker', highlight: 'Todo'},
  blockquote_marker: {type: 'LspMarkdownBlockquoteMarker', highlight: 'Comment'},
  code_fence: {type: 'LspMarkdownCodeFence', highlight: 'Type'},
  language: {type: 'LspMarkdownLanguage', highlight: 'Type'}
}

# Map marker names to prop type keys for GetMarkerProp
const MARKER_PROP_MAP = {
  emphasis: 'italic',
  strong: 'bold',
  code_span: 'code_span',
  heading: 'heading',
  code_block: 'code_block',
  list_item: 'list_item',
  table_header: 'table_header',
  table_sep: 'table_sep',
  strikethrough: 'strikethrough',
  thematic_break: 'thematic_break',
  link: 'link',
  task_marker: 'task_marker',
  blockquote_marker: 'blockquote_marker',
  code_fence: 'code_fence',
  language: 'language'
}

# ============================================================================
# TEXT PROPERTY AND HIGHLIGHT INITIALIZATION
# ============================================================================

# Initialize text property highlights and types
for name in PROP_TYPES->keys()
  var prop_config = PROP_TYPES[name]
  execute $'highlight default link {prop_config.type} {prop_config.highlight}'
  prop_type_add(prop_config.type, {highlight: prop_config.highlight})
endfor

# Override specific highlights that don't use link
highlight LspBold term=bold cterm=bold gui=bold
highlight LspItalic term=italic cterm=italic gui=italic
highlight LspStrikeThrough term=strikethrough cterm=strikethrough gui=strikethrough

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Create a text property for a given marker type
def GetMarkerProp(marker: string, col: number, ...opt: list<any>): dict<any>
  var prop_key = MARKER_PROP_MAP->get(marker, '')
  if prop_key == ''
    return {}
  endif

  var prop_config = PROP_TYPES[prop_key]
  var result = {type: prop_config.type, col: col}

  # Code blocks use end position instead of length
  if marker == 'code_block'
    result.end_lnum = opt[0]
    result.end_col = opt[1]
  else
    result.length = opt[0]
  endif

  return result
enddef

# Check if a text range overlaps with any existing properties of specific types
def IsRangeOverlapped(props: list<dict<any>>, col: number, length: number, ...types: list<string>): bool
  if length <= 0
    return false
  endif

  var range_start = col
  var range_end = col + length - 1

  for prop in props
    var p_len = prop->get('length', 0)
    if p_len == 0 || types->index(prop.type) < 0
      continue
    endif

    var prop_end = prop.col + p_len - 1
    if range_start <= prop_end && range_end >= prop.col
      return true
    endif
  endfor

  return false
enddef

# ============================================================================
# INLINE ELEMENT PARSING
# ============================================================================

# Detect and add properties for automatic links (URLs and email addresses)
def AddAutoLinkProps(text: string, props: list<dict<any>>, rel_pos: number): list<dict<any>>
  var link_props: list<dict<any>> = []
  var patterns = [
    '<https\?://[^>[:space:]]\+>',
    'https\?://[[:alnum:]][[:alnum:]/?&=#._~%:+-]*',
    '\<www\.[[:alnum:]][[:alnum:]/?&=#._~%:+-]*',
    '\<[[:alnum:]._%+-]\+@[[:alnum:].-]\+\.[[:alpha:]]\{2,}\>'
  ]

  var text_len = text->len()
  for pattern in patterns
    var pos = 0
    while pos < text_len
      var matched = text->matchstrpos(pattern, pos)
      if matched[1] < 0
	break
      endif
      var raw = matched[0]
      var start_col = matched[1] + 1
      var length = raw->len()
      if raw[0] == '<' && raw[-1] == '>'
	start_col += 1
	length -= 2
      endif
      var trimmed = text->strpart(start_col - 1, length)->substitute('[.,;:!?]\+$', '', '')
      var trimmed_len = trimmed->len()
      if trimmed_len > 0
	if !IsRangeOverlapped(props, start_col, trimmed_len, 'LspMarkdownCode')
	    && !IsRangeOverlapped(link_props, rel_pos + start_col, trimmed_len, 'LspMarkdownLink')
	  var link_prop = GetMarkerProp('link', rel_pos + start_col, trimmed_len)
	  var insert_idx = 0
	  var props_len = link_props->len()
	  while insert_idx < props_len && link_props[insert_idx].col <= link_prop.col
	    insert_idx += 1
	  endwhile
	  link_props->insert(link_prop, insert_idx)
	endif
      endif
      pos = matched[2]
    endwhile
  endfor

  return link_props
enddef

# Add task checkbox marker properties ([ ], [x], [X]) to list items
def AddTaskMarkerProp(line: dict<any>): void
  var line_len = line.text->len()
  for prop in line.props
    if prop.type != 'LspMarkdownListMarker'
      continue
    endif
    var start = prop.col + prop.length
    if start + 2 <= line_len && line.text->strpart(start - 1, 3) =~ '^\[[ xX]\]$'
      line.props->add(GetMarkerProp('task_marker', start, 3))
    endif
    break
  endfor
enddef

# Extract all code spans (backtick-delimited inline code) from text
def GetCodeSpans(text: string): list<dict<any>>
  var code_spans = []
  var search_pos = 0
  var text_len = text->len()

  while search_pos < text_len
    # Find next backtick (handling escaped backticks)
    var backtick = text->matchstrpos('\\*`', search_pos)
    if backtick[1] < 0
      break
    endif

    # Check if backtick is escaped (even number of backslashes)
    if backtick[0]->len() % 2 == 0
      search_pos = backtick[2]
      continue
    endif

    search_pos = backtick[2] - 1

    # Match complete code span with matching delimiter
    var code_span = text->matchstrpos('^\(`\+\)`\@!.\{-}`\@1<!\1`\@!', search_pos)
    if code_span[1] < 0
      break
    endif

    # Extract inner code text (trimming space if present)
    var code_text = text->matchstrpos('^\(`\+\)\%(\zs \+\ze\|\([ \n]\=\)\zs.\{-}\S.\{-}\ze\2\)`\@1<!\1`\@!', search_pos)

    code_spans->add({
      marker: '`',
      start: [code_span[1], code_text[1]],
      end: [code_text[2], code_span[2]]
    })

    search_pos = code_span[2]
  endwhile

  return code_spans
enddef

# Unescape markdown escape sequences and normalize whitespace
def Unescape(text: string, block_marker: string = ""): string
  if block_marker == '`'
    # Line breaks do not occur inside code spans
    return text->substitute('\n', ' ', 'g')
  endif

  # Handle hard line breaks (backslash followed by newline)
  var result = text->substitute('\\\@<!\(\(\\\\\)*\)\\\n', '\1  \n', 'g')

  # Change soft line breaks to spaces
  result = result->substitute(' \@<! \=\n', ' ', 'g')

  # Change hard line breaks (2+ spaces) to single newline
  result = result->substitute(' \{2,}\n', '\n', 'g')

  # Replace non-breaking spaces
  result = result->substitute('&nbsp;', ' ', 'g')

  # Unescape only markdown punctuation characters (preserve \u sequences)
  var punct = '!"#$%&' .. "'" .. '()*+,-./:;<=>?@[\]^_`{|}~'
  return result->substitute('\\\([' .. punct .. ']\)', '\1', 'g')
enddef

def DecodeHtmlEntities(text: string): string
  # Map of simple entity replacements
  var entities = {
    '&nbsp;': ' ',
    '&lt;':   '<',
    '&gt;':   '>',
    '&amp;':  '&',
    '&quot;': '"',
    '&apos;': "'"
  }

  # Single regex to match all entities, hex codes, and decimal codes
  var pattern = '&\(nbsp\|lt\|gt\|amp\|quot\|apos\);\|&#\([0-9]\+\);\|&#x\([0-9a-fA-F]\+\);'

  return text->substitute(pattern, (m) => {
    if m[1] != ''      # Named entity
      return entities[m[0]]
    elseif m[2] != ''  # Decimal &#123;
      return nr2char(str2nr(m[2]))
    else               # Hex &#xABC;
      return nr2char(str2nr(m[3], 16))
    endif
  }, 'g')
enddef

# ============================================================================
# REFERENCE LINKS AND SYNTAX HIGHLIGHTING
# ============================================================================

var reference_defs: dict<string> = {}
var syntax_exists_cache: dict<bool> = {}

# Check if syntax highlighting is available for a given language
def HasSyntaxForLanguage(language: string): bool
  if syntax_exists_cache->has_key(language)
    return syntax_exists_cache[language]
  endif
  var has_syntax = !globpath(&rtp, $'syntax/{language}.vim')->empty()
  syntax_exists_cache[language] = has_syntax

  return has_syntax
enddef

# Normalize reference label for lookup (lowercase, collapse whitespace)
def NormalizeReferenceLabel(label: string): string
  return label->tolower()->substitute('\s\+', ' ', 'g')->trim()
enddef

# Resolve reference link to display text or return original if not found
def ResolveReferenceText(link_text: string, label: string, full_match: string): string
  var key = NormalizeReferenceLabel(label->empty() ? link_text : label)
  if reference_defs->has_key(key)
    return link_text
  endif

  return full_match
enddef

def ResolveReferenceLinks(text: string): string
  if reference_defs->empty()
    return text
  endif
  return text->substitute('!\[\([^][]\+\)\]\[\([^][]*\)\]',
    '\=ResolveReferenceText(submatch(1), submatch(2), submatch(0))',
    'g')
  ->substitute('\%(^\|[^!]\)\zs\[\([^][]\+\)\]\[\([^][]*\)\]',
    '\=ResolveReferenceText(submatch(1), submatch(2), submatch(0))',
    'g')
  ->substitute('\%(^\|[^!]\)\zs\[\([^][]\+\)\]\ze\%([^[(]\|$\)',
    '\=ResolveReferenceText(submatch(1), submatch(1), submatch(0))',
    'g')
enddef

def StripInlineLinks(text: string): string
  var result = ResolveReferenceLinks(text)
    ->substitute('<\(https\?://[^>[:space:]]\+\)>', '\1', 'g')
    ->substitute('<\([^< >]\+@[^< >]\+\)>', '\1', 'g')
    # Handle links - must preserve link text, remove link syntax
    # Empty URL: [text]()
    ->substitute('\!\=\[\([^][]*\)\](\s*)', '\1', 'g')
    # URL with angle brackets and optional title: [text](<url> "title")
    ->substitute('\!\=\[\([^][]*\)\](\s*<[^>]\+>\s*\%("[^"]*"\|''[^'']*''\|(\([^)]\|\\.\)*)\)\=\s*)', '\1', 'g')
    # URL (possibly with parens) and optional title: [text](url "title")
    ->substitute('\!\=\[\([^][]*\)\](\s*[^()[:space:]]\+\%(([^()]*)[^()[:space:]]*\)*\s*\%("[^"]*"\|''[^'']*''\|(\([^)]\|\\.\)*)\)\=\s*)', '\1', 'g')

  # Fallback for complex nested cases
  while true
    var stripped = result->substitute('\!\=\[\([^][]\+\)\](\s*[^)]\+\s*)', '\1', 'g')
    if stripped == result
      break
    endif
    result = stripped
  endwhile

  return result
enddef

# Preprocess inline text: strip links, detect code spans, decode HTML entities
def PreprocessInlineText(text: string): string
  var text_no_links = StripInlineLinks(text)
  var code_spans = GetCodeSpans(text_no_links)

  if code_spans->empty()
    return DecodeHtmlEntities(text_no_links)
  endif

  # Decode HTML entities only outside code spans
  var result = ''
  var search_pos = 0
  var text_len = text_no_links->len()

  for span in code_spans
    # Decode text before code span
    if search_pos < span.start[0]
      var segment = text_no_links->strpart(search_pos, span.start[0] - search_pos)
      result ..= DecodeHtmlEntities(segment)
    endif

    # Preserve code span content exactly (no HTML decoding)
    result ..= text_no_links->strpart(span.start[0], span.end[1] - span.start[0])
    search_pos = span.end[1]
  endfor

  # Decode remaining text after last code span
  if search_pos < text_len
    result ..= DecodeHtmlEntities(text_no_links->strpart(search_pos))
  endif

  return result
enddef

# Find the next emphasis/strikethrough delimiter in text
def GetNextInlineDelimiter(text: string, start_pos: number, end_pos: number): dict<any>
  var search_pos = start_pos
  var text_len = text->len()

  while search_pos < text_len
    # Search for first delimiter character (_, *, ~)
    var delimiter = text->matchstrpos('\\*[_*~]', search_pos)
    if delimiter[1] < 0 || delimiter[1] > end_pos
      return {}
    endif

    # Check if delimiter is escaped
    if delimiter[0]->len() % 2 == 0
      search_pos = delimiter[2]
      continue
    endif

    search_pos = delimiter[2] - 1

    # Match the complete delimiter run (e.g., **, ___, ~~)
    var delim_char_escaped = delimiter[0][-1]->substitute('\([*~]\)', '\\\1', 'g')
    var delimiter_run = text->matchstrpos($'{delim_char_escaped}\+', search_pos)

    # Strikethrough must be exactly ~~, not longer
    if delimiter_run[0][0] == '~' && delimiter_run[0]->len() > 2
      search_pos = delimiter_run[2]
      continue
    endif

    # Adjust position for boundary checking
    var check_pos = search_pos
    var pos_prefix = ''
    if search_pos > 0
      check_pos -= 1
      pos_prefix = '.'
    endif

    var delim_escaped = delimiter_run[0]->substitute('\([*~]\)', '\\\1', 'g')

    # Check if delimiter can open emphasis (left-flanking)
    var is_left = text->match(
      $'^{pos_prefix}{delim_escaped}\%(\s\|$\|{PUNCTUATION}\)\@!\|' ..
      $'^{pos_prefix}\%(\s\|^\|{PUNCTUATION}\)\@1<={delim_escaped}{PUNCTUATION}',
      check_pos) >= 0

    # Check if delimiter can close emphasis (right-flanking)
    var is_right = text->match(
      $'^{pos_prefix}\%(\s\|^\|{PUNCTUATION}\)\@1<!{delim_escaped}\|' ..
      $'^{pos_prefix}{PUNCTUATION}\@1<={delim_escaped}\%(\s\|$\|{PUNCTUATION}\)',
      check_pos) >= 0

    if !is_left && !is_right
      search_pos = delimiter_run[2]
      continue
    endif

    # Apply GFM emphasis rules for underscores
    if delimiter_run[0][0] == '_'
      var preceded_by_word = delimiter_run[1] > 0 && text[delimiter_run[1] - 1] =~ '\w'
      var followed_by_word = delimiter_run[2] < text_len && text[delimiter_run[2]] =~ '\w'

      # Underscore intra-word emphasis is disallowed in GFM
      if preceded_by_word && followed_by_word
	search_pos = delimiter_run[2]
	continue
      endif
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
  while !blocks->empty() && cur.end[0] >= blocks[0].start[0]
    result.text ..= Unescape(text->strpart(pos, blocks[0].start[0] - pos), cur.marker[0])
    # get nested block
    var part = GetNextInlineBlock(text, blocks, rel_pos + result.text->len())
    result.text ..= part.text
    result.props += part.props
    pos = part.end_pos
  endwhile
  result.text ..= Unescape(text->strpart(pos, cur.end[0] - pos), cur.marker[0])
  # Add props for current inline block using type map
  result.props->insert(GetMarkerProp(INLINE_PROP_TYPES[cur.marker],
    rel_pos + 1,
    result.text->len()))
  result->extend({'end_pos': cur.end[1]})

  return result
enddef

# Match right delimiter with left delimiters in sequence
def MatchRightDelimiter(delimiter: dict<any>, seq: list<any>): void
  var idx = seq->len() - 1

  while idx >= 0
    # Skip if different marker type or already closed
    if delimiter.marker[0] != seq[idx].marker[0] || seq[idx]->has_key('end')
      idx -= 1
      continue
    endif

    var delimiter_len = delimiter.marker->len()
    var seq_marker_len = seq[idx].marker->len()

    # Apply GFM rule: check sum rule for emphasis matching
    if delimiter.left || seq[idx].right
      if (delimiter_len + seq_marker_len) % 3 == 0
	  && (delimiter_len % 3 > 0 || seq_marker_len % 3 > 0)
	idx -= 1
	continue
      endif
    endif

    # Match with minimum of delimiter lengths (max 2 for strong)
    var marker_len = min([delimiter_len, seq_marker_len, 2])

    # If left delimiter is longer, split it
    if seq_marker_len > marker_len
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

    # Mark the emphasis span as complete
    seq[idx]->extend({
      end: [delimiter.start[0], delimiter.start[0] + marker_len]
    })

    # Remove unclosed overlapped emphasis spans
    for i in range(seq->len() - 1, idx + 1, -1)
      if !seq[i]->has_key('end')
	seq->remove(i)
      endif
    endfor

    # Update delimiter if partially consumed
    if delimiter_len > marker_len
      delimiter.start[0] += marker_len
    else
      delimiter.left = false
      break
    endif

    idx -= 1
  endwhile
enddef

# Find and match all emphasis delimiters in text
def FindEmphasisMatches(input_text: string, code_spans: list<dict<any>>): list<dict<any>>
  var search_pos = 0
  var seq = []
  var text_len = input_text->len()

  var span_idx = 0
  var num_spans = code_spans->len()

  # Search all emphasis delimiters
  while search_pos < text_len
    var code_pos_start = text_len
    var code_pos_end = text_len

    # Handle code spans (skip emphasis inside code)
    if span_idx < num_spans
      var span = code_spans[span_idx]
      code_pos_start = span.start[0]
      code_pos_end = span.end[1]

      if search_pos >= code_pos_start
        search_pos = code_pos_end
        seq->add(span)
        span_idx += 1
        continue
      endif
    endif

    # Find next delimiter before the next code span
    var delimiter = GetNextInlineDelimiter(input_text, search_pos, code_pos_start)

    if delimiter->empty()
      # Jump to the end of the current code span if we found nothing before it
      search_pos = code_pos_end
      continue
    endif

    # Try to match right delimiters with left ones
    if delimiter.right
      MatchRightDelimiter(delimiter, seq)
    endif

    # Add left delimiters to sequence
    if delimiter.left
      seq->add(delimiter)
    endif

    search_pos = delimiter.start[1]
  endwhile

  # Add remaining code spans
  if span_idx < num_spans
    seq->extend(code_spans[span_idx :])
  endif

  # Remove unclosed delimiters
  # This keeps only matched emphasis blocks and all code spans
  return seq->filter((_, val) => val->has_key('end'))
enddef

# Compose formatted text from inline blocks with text properties
def ComposeFormattedText(input_text: string, seq: list<dict<any>>, rel_pos: number): dict<any>
  var formatted = {
    text: '',
    props: []
  }
  var search_pos = 0
  var text_len = input_text->len()

  while !seq->empty()
    # Add unformatted text before next inline block
    if search_pos < seq[0].start[0]
      formatted.text ..= Unescape(input_text->strpart(search_pos, seq[0].start[0] - search_pos))
      search_pos = seq[0].start[0]
    endif

    # Process inline block (emphasis, code, etc.)
    var inline = GetNextInlineBlock(input_text, seq, rel_pos + formatted.text->len())
    formatted.text ..= inline.text
    formatted.props += inline.props
    search_pos = inline.end_pos
  endwhile

  # Add remaining unformatted text
  if search_pos < text_len
    formatted.text ..= Unescape(input_text->strpart(search_pos))
  endif

  # Add automatic link detection
  formatted.props += AddAutoLinkProps(formatted.text, formatted.props, rel_pos)

  return formatted
enddef

# Main function to parse all inline elements (emphasis, code, links, etc.)
def ParseInlines(text: string, rel_pos: number = 0): dict<any>
  var input_text = PreprocessInlineText(text)
  var code_spans = GetCodeSpans(input_text)

  # Find and match all emphasis delimiters
  var matches = FindEmphasisMatches(input_text, code_spans)

  # Compose final text with properties
  return ComposeFormattedText(input_text, matches, rel_pos)
enddef

# ============================================================================
# BLOCK STRUCTURE CREATION
# ============================================================================

# Create a new container block (quote or list item)
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

# Create a new leaf block (code, paragraph, heading, table, etc.)
def CreateLeafBlock(block_type: string, line: string, ...opt: list<any>): dict<any>
  if block_type == 'fenced_code'
    var token = line->matchlist(CODE_FENCE)
    return {
      type: block_type,
      fence: token[1],
      language: token[2],
      text: []
    }
  elseif block_type == 'indented_code'
    return {
      type: block_type,
      text: [line->matchstr(CODE_INDENT)]
    }
  elseif block_type == 'paragraph'
    return {
      type: block_type,
      text: [line->matchstr(PARAGRAPH)]
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

# ============================================================================
# DOCUMENT RENDERING
# ============================================================================

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
  if lang != '' && HasSyntaxForLanguage(lang)
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

    line.props->add(GetMarkerProp('code_block', line_text_len + 1, final_lnum, max_line_len + 1))
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
  var format = ParseInlines(block.text, line.text->len())
  line.props->add(GetMarkerProp('heading',
		  line.text->len() + 1,
		  format.text->len(),
		  block.level))

  line.text ..= format.text
  line.props += format.props
  AddTaskMarkerProp(line)
  document.content += SplitLine(line)
enddef

# Append table cells to line with proper formatting and properties
def AppendTableCells(line: dict<any>, cells: list<string>, is_header: bool): void
  var first_cell = cells->remove(0)->substitute('\\|', '|', 'g')
  var line_len = line.text->len()
  var format = ParseInlines(first_cell, line_len)

  if is_header
    line.props->add(GetMarkerProp('table_header', line_len + 1, format.text->len()))
  endif

  line.text ..= format.text
  line.props += format.props

  for cell_text in cells
    var col_text = cell_text->substitute('\\|', '|', 'g')
    line_len = line.text->len()
    format = ParseInlines(col_text, line_len + 1)

    line.props->add(GetMarkerProp('table_sep', line_len + 1, 1))
    if is_header
      line.props->add(GetMarkerProp('table_header', line_len + 2, format.text->len()))
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
    props: [GetMarkerProp('table_sep', indent->len() + 1, block.delimiter->len())]
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
  var format = ParseInlines(block.text->join("\n")->substitute('\s\+$', '', ''), line.text->len())

  line.text ..= format.text
  line.props += format.props
  AddTaskMarkerProp(line)
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
    line.props->add(GetMarkerProp('list_item',
				  current_text_len + 1,
				  marker_len))
    line.text ..= block.marker
    block.marker = ' '->repeat(marker_len)
  else
    line.text ..= block.marker
  endif
enddef

var last_block: string = ''

# Close and render blocks from start index onwards
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

# ============================================================================
# BLOCK PARSING - LINE PROCESSING
# ============================================================================

# Expand tabs to spaces in block markers (preserves tab stops)
def ExpandTabs(line: string): string
  var block_marker = line->matchstrpos($'^ \{{,3}}>[ \t]\+\|^[ \t]*\%({LIST_MARKER}\)\=[ \t]*')
  if block_marker[0]->match('\t') < 0
    return line
  endif
  var begin: string = ""
  var begin_len = 0
  for char in block_marker[0]
    if char == '	'
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
def FilterLinkReferences(data: list<string>): list<string>
  var filtered_data: list<string> = []
  var idx = 0
  var data_len = data->len()

  while idx < data_len
    var line = data[idx]
    var ref = line->matchlist(LINK_REFERENCE_DEF)

    if ref->len() > 0
      # Store reference definition
      reference_defs[NormalizeReferenceLabel(ref[1])] = ref[2]

      # Check if next line is continuation with title
      if idx + 1 < data_len && data[idx + 1] =~ LINK_REFERENCE_TITLE_CONT
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
    var marker = line->matchstrpos(BLOCK_QUOTE)
    if marker[1] == -1
      return [false, line]
    endif
    return [true, line->strpart(marker[2])]
  elseif block.type == 'list_item'
    # New list item at same/outer level should stop continuation
    var new_list_match = line->matchstrpos(list_item)
    if new_list_match[1] >= 0 && new_list_match[1] < block.indent
      return [false, line]
    endif
    var marker = line->matchstrpos($'^ \{{{block.indent}}}')
    if marker[1] == -1
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
  if line =~ SETEXT_HEADING
    var marker = line->matchstrpos(SETEXT_HEADING)
    var heading_text = open_blocks->remove(cur).text->join("\n")->substitute('\s\+$', '', '')
    open_blocks->add(CreateLeafBlock('heading', heading_text, SETEXT_HEADING_LEVEL[marker[0][0]]))
    CloseBlocks(document, open_blocks, cur)
    return [true, false]
  endif

  # Check for table delimiter (only for single-line paragraphs)
  if open_blocks[cur].text->len() == 1
    var delimiter = line->matchstr(TABLE_DELIMITER)
    if !delimiter->empty()
      var header_cols = open_blocks[cur].text[0]->split('\\\@1<!|')->len()
      var delimiter_cols = delimiter->split('|')->len()

      if header_cols == delimiter_cols
	open_blocks->add(CreateLeafBlock('table', open_blocks->remove(cur).text[0], delimiter))
	return [true, false]
      endif
    endif
  endif

  return [false, true]
enddef

# Handle terminal open blocks (fenced code, indented code, HTML)
def HandleTerminalOpenBlock(line: string, cur: number,
			    open_blocks: list<dict<any>>, document: dict<list<any>>): list<any>
  # Returns [handled, consumed, should_break]
  var block = open_blocks[cur]

  if block.type == 'fenced_code'
    var fence_char = block.fence[0]->escape('\^$.*[]~')
    var fence_pattern = fence_char->repeat(block.fence->len())

    if line =~ $'^ \{{,3}}{fence_pattern}{fence_char}* *$'
      # Closing fence found
      CloseBlocks(document, open_blocks, cur)
    else
      # Add line to code block
      block.text->add(line)
    endif
    return [true, true, false]

  elseif block.type == 'indented_code'
    var marker = line->matchstrpos(CODE_INDENT)
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

# Process open blocks to see how many the current line continues
def ProcessOpenBlocks(line_in: string, open_blocks: list<dict<any>>, document: dict<list<any>>): list<any>
  # Returns [processed_line, block_index, consumed]
  var line = line_in
  var cur = 0

  while cur < open_blocks->len()
    var block = open_blocks[cur]

    if block.type =~ 'quote_block\|list_item'
      # Handle container blocks
      var continued = ContinueContainerBlock(line, block)
      if !continued[0]
	break
      endif
      line = continued[1]

    else
      # Handle leaf blocks
      var terminal = HandleTerminalOpenBlock(line, cur, open_blocks, document)
      if terminal[0]
	if terminal[1]
	  return [line, -1, true]
	endif
	if terminal[2]
	  break
	endif

      elseif block.type == 'paragraph'
	var para_result = HandleParagraphContinuation(line, cur, open_blocks, document)
	if para_result[0]
	  return [line, -1, true]
	endif
	if para_result[1]
	  break
	endif
      endif
    endif

    cur += 1
  endwhile

  return [line, cur, false]
enddef

# Handle thematic break (horizontal rule)
def HandleThematicBreak(line: string, open_blocks: list<dict<any>>, document: dict<list<any>>, width: number): bool
  if line !~ THEMATIC_BREAK
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
    props: [GetMarkerProp('thematic_break', 1, hr_text->len())]
  })
  last_block = 'hr'

  return true
enddef

# Detect and create new container blocks (quotes, lists)
def HandleNewContainerBlocks(line_in: string, open_blocks: list<dict<any>>, document: dict<list<any>>, cur: number): list<any>
  # Returns [remaining_line, new_cur]
  var line = line_in
  var new_cur = cur

  while true
    var block_match = line->matchstrpos($'{BLOCK_QUOTE}\|{list_item}')
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

  if line =~ CODE_FENCE
    CloseBlocks(document, open_blocks, cur)
    open_blocks->add(CreateLeafBlock('fenced_code', line))
  elseif line =~ BLANK_LINE
    if open_blocks->empty()
      return [line, cur]
    endif
    if open_blocks[-1].type == 'paragraph'
      CloseBlocks(document, open_blocks, min([cur, open_blocks->len() - 1]))
    elseif open_blocks[-1].type == 'table'
      CloseBlocks(document, open_blocks, open_blocks->len() - 1)
    elseif open_blocks[-1].type =~ '_code'
      open_blocks[-1].text->add(line)
    endif
  elseif line =~ CODE_INDENT
    if open_blocks->empty()
      open_blocks->add(CreateLeafBlock('indented_code', line))
    elseif open_blocks[-1].type =~ '_code'
      open_blocks[-1].text->add(line->matchstr(CODE_INDENT))
    elseif open_blocks[-1].type == 'paragraph'
      open_blocks[-1].text->add(line->matchstr(PARAGRAPH))
    else
      CloseBlocks(document, open_blocks, cur)
      open_blocks->add(CreateLeafBlock('indented_code', line))
    endif
  elseif line =~ ATX_HEADING
    CloseBlocks(document, open_blocks, cur)
    var token = line->matchlist(ATX_HEADING)
    var heading_text = token->len() > 2 ? token[2] : ''
    open_blocks->add(CreateLeafBlock('heading', heading_text, token[1]->len()))
    CloseBlocks(document, open_blocks, cur)
  elseif line =~ HTML_COMMENT_OPEN
    CloseBlocks(document, open_blocks, cur)
    open_blocks->add(CreateLeafBlock('html_comment', line))
    if line =~ '^ \{,3}-->'
      CloseBlocks(document, open_blocks, cur)
    endif
  elseif line =~ HTML_BLOCK_OPEN
    CloseBlocks(document, open_blocks, cur)
    var html_token = line->matchlist(HTML_BLOCK_OPEN)
    open_blocks->add(CreateLeafBlock('html_block', line, html_token[1]))
    if line =~ $'^ \{{,3}}</{html_token[1]}>\s*$'
      CloseBlocks(document, open_blocks, cur)
    endif
  elseif new_containers_created
    # New containers were just created, add remaining text as leaf block
    if line->len() > 0
      open_blocks->add(CreateLeafBlock('paragraph', line))
    endif
  elseif !open_blocks->empty()
    if open_blocks[-1].type == 'table'
      open_blocks[-1].text->add(line)
    elseif open_blocks[-1].type == 'paragraph'
      open_blocks[-1].text->add(line->matchstr(PARAGRAPH))
    elseif open_blocks[-1].type == 'list_item'
      # Check if line is a new list item at same/outer indentation level
      if line->len() > 0 && line[0] != ' ' && line =~ '^\([-+*]\|[0-9]\+[.)]\) '
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
    else
      CloseBlocks(document, open_blocks, cur)
      open_blocks->add(CreateLeafBlock('paragraph', line))
    endif
  else
    open_blocks->add(CreateLeafBlock('paragraph', line))
  endif

  return [line, cur]
enddef

# ============================================================================
# MAIN MARKDOWN PARSER
# ============================================================================

# Parse markdown text into structured document with text properties
export def ParseMarkdown(data: list<string>, width: number = 80): dict<list<any>>
  var document: dict<list<any>> = {content: [], syntax: []}
  var open_blocks: list<dict<any>> = []
  reference_defs = {}

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
