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
  html_comment_open: '^ \{,3\}<!--\s*$',
  atx_heading: '^ \{,3\}\zs\(#\{1,6\}\)\%( \s*\(.\{-}\)\s*\ze\%( #\{1,}\s*\)\=\)\=$',
  setext_heading: '^ \{,3\}\zs\%(=\{1,}\|-\{1,}\)\ze *$',
  table_delimiter: '^|\=\zs *:\=-\{1,}:\= *\%(| *:\=-\{1,}:\= *\)*\ze|\=$',
  link_reference_def: '^ \{,3\}\[\([^][]\+\)\]:\s*\(\S\+\)\%(.\{-}\)\=$',
  link_reference_title_cont: '^ \{1,3\}\%(".*"\|(.*)\|''.*''\)\s*$',
  punctuation: "[!\"#$%&'()*+,-./:;<=>?@[\\\\\\]^_`{|}~]"
}

# Expose shortcuts for frequently used patterns
export const BLOCK_QUOTE = MARKDOWN_PATTERNS.block_quote
export const LIST_MARKER = MARKDOWN_PATTERNS.list_marker
export const BLANK_LINE = MARKDOWN_PATTERNS.blank_line
export const THEMATIC_BREAK = MARKDOWN_PATTERNS.thematic_break
export const CODE_FENCE = MARKDOWN_PATTERNS.code_fence
export const CODE_INDENT = MARKDOWN_PATTERNS.code_indent
export const PARAGRAPH = MARKDOWN_PATTERNS.paragraph
export const HTML_BLOCK_OPEN = MARKDOWN_PATTERNS.html_block_open
export const HTML_COMMENT_OPEN = MARKDOWN_PATTERNS.html_comment_open
export const ATX_HEADING = MARKDOWN_PATTERNS.atx_heading
export const SETEXT_HEADING = MARKDOWN_PATTERNS.setext_heading
export const TABLE_DELIMITER = MARKDOWN_PATTERNS.table_delimiter
export const LINK_REFERENCE_DEF = MARKDOWN_PATTERNS.link_reference_def
export const LINK_REFERENCE_TITLE_CONT = MARKDOWN_PATTERNS.link_reference_title_cont
export const PUNCTUATION = MARKDOWN_PATTERNS.punctuation

# Computed patterns
export const SETEXT_HEADING_LEVEL = {'=': 1, '-': 2}
export const list_item = '^\([-+*]\|[0-9]\+[.)]\)\ze\s*$\|^ \{,3\}\zs\([-+*]\|[0-9]\+[.)]\) \{1,4\}\ze\S\|^ \{,3\}\zs\([-+*]\|[0-9]\+[.)]\) \{5}\ze\s*\S'

# ============================================================================
# MARKDOWN CONFIGURATION CONSTANTS
# ============================================================================

# Structural constants for markdown parsing
export const MIN_CODE_FENCE_LENGTH = 3  # Minimum backticks/tildes for code fence
export const CODE_INDENT_WIDTH = 4      # Spaces required for indented code block
export const LIST_INDENT_MAX = 4        # Max spaces before list marker content
export const TAB_STOP_WIDTH = 4         # Tab expansion width
export const EMPHASIS_WEIGHT_THRESHOLD = 3  # GFM rule for emphasis matching

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
# Returns property dict with type, col, and either length or end_lnum/end_col
export def GetMarkerProp(marker: string, col: number, ...opt: list<any>): dict<any>
  var prop_key = MARKER_PROP_MAP->get(marker, '')
  if prop_key == ''
    return {}
  endif

  var prop_config = PROP_TYPES[prop_key]
  var result = {type: prop_config.type, col: col}

  # Code blocks span multiple lines using end position
  if marker == 'code_block'
    result.end_lnum = opt[0]
    result.end_col = opt[1]
  else
    result.length = opt[0]
  endif

  return result
enddef

# Check if a text range overlaps with any existing properties of specific types
# Optimization: O(1) intersection check instead of O(n) element-wise comparison
export def IsRangeOverlapped(props: list<dict<any>>, col: number, length: number, ...types: list<string>): bool
  if length <= 0
    return false
  endif

  # Convert types list to dict for O(1) membership testing
  var type_set: dict<bool> = {}
  for t in types
    type_set[t] = true
  endfor

  var range_start = col
  var range_end = col + length - 1

  for prop in props
    var p_len = prop->get('length', 0)
    if p_len == 0 || !type_set->has_key(prop.type)
      continue
    endif

    var prop_end = prop.col + p_len - 1
    # Two ranges overlap if one starts before the other ends
    if range_start <= prop_end && range_end >= prop.col
      return true
    endif
  endfor

  return false
enddef

var syntax_exists_cache: dict<bool> = {}

# Check if syntax highlighting is available for a given language
# Caching optimization: globpath is expensive, cache results per language
export def HasSyntaxForLanguage(language: string): bool
  if syntax_exists_cache->has_key(language)
    return syntax_exists_cache[language]
  endif
  var has_syntax = !globpath(&rtp, $'syntax/{language}.vim')->empty()
  syntax_exists_cache[language] = has_syntax

  return has_syntax
enddef

# ============================================================================
# ESCAPE AND TYPE CHECKING HELPERS
# ============================================================================

# Check if a matched character sequence is escaped (preceded by odd backslashes)
# Example: \\\* has 2 backslashes before *, so * is escaped (matched_text = "\\\*")
export def IsEscaped(matched_text: string): bool
  return matched_text->len() % 2 == 0
enddef

# Check if a block is a container block (quote or list item)
export def IsContainerBlock(block: dict<any>): bool
  return block.type =~ 'quote_block\|list_item'
enddef

# Check if a block is a leaf block (not a container)
export def IsLeafBlock(block: dict<any>): bool
  return !IsContainerBlock(block)
enddef

# Check if a block is any type of code block
export def IsCodeBlock(block: dict<any>): bool
  return block.type =~ '_code'
enddef

# Check if a block is a paragraph block
export def IsParagraphBlock(block: dict<any>): bool
  return block.type == 'paragraph'
enddef

# Check if a block is a table block
export def IsTableBlock(block: dict<any>): bool
  return block.type == 'table'
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
