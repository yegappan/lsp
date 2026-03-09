vim9script

import './constants.vim' as c

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

var reference_defs: dict<string> = {}
var normalized_labels_cache: dict<string> = {}

export def SetReferenceDefinitions(refs: dict<string>): void
  reference_defs = refs
  # Clear cache when new references are set
  normalized_labels_cache = {}
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
	if !c.IsRangeOverlapped(props, start_col, trimmed_len, 'LspMarkdownCode')
	    && !c.IsRangeOverlapped(link_props, rel_pos + start_col, trimmed_len, 'LspMarkdownLink')
	  var link_prop = c.GetMarkerProp('link', rel_pos + start_col, trimmed_len)
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
export def AddTaskMarkerProp(line: dict<any>): void
  var line_len = line.text->len()
  for prop in line.props
    if prop.type != 'LspMarkdownListMarker'
      continue
    endif
    var start = prop.col + prop.length
    if start + 2 <= line_len && line.text->strpart(start - 1, 3) =~ '^\[[ xX]\]$'
      line.props->add(c.GetMarkerProp('task_marker', start, 3))
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
    if c.IsEscaped(backtick[0])
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
def NormalizeMarkdownLineBreaks(text: string): string
  # Handle hard line breaks (backslash followed by newline)
  var result = text->substitute('\\\@<!\(\(\\\\\)*\)\\\n', '\1  \n', 'g')

  # Change soft line breaks to spaces
  result = result->substitute(' \@<! \=\n', ' ', 'g')

  # Change hard line breaks (2+ spaces) to single newline
  result = result->substitute(' \{2,}\n', '\n', 'g')

  # Replace non-breaking spaces
  return result->substitute('&nbsp;', ' ', 'g')
enddef

def UnescapeMarkdownPunctuation(text: string): string
  # Unescape only markdown punctuation characters (preserve \u sequences)
  var punct = '!"#$%&' .. "'" .. '()*+,-./:;<=>?@[\]^_`{|}~'
  return text->substitute('\\\([' .. punct .. ']\)', '\1', 'g')
enddef

def Unescape(text: string, block_marker: string = ""): string
  if block_marker == '`'
    # Line breaks do not occur inside code spans
    return text->substitute('\n', ' ', 'g')
  endif

  var result = NormalizeMarkdownLineBreaks(text)
  return UnescapeMarkdownPunctuation(result)
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

# Normalize reference label for lookup (lowercase, collapse whitespace)
# Caching optimization: avoids repeated normalization of same labels
export def NormalizeReferenceLabel(label: string): string
  if normalized_labels_cache->has_key(label)
    return normalized_labels_cache[label]
  endif

  var normalized = label->tolower()->substitute('\s\+', ' ', 'g')->trim()
  normalized_labels_cache[label] = normalized
  return normalized
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

def StripSimpleInlineLinks(text: string): string
  return text
    ->substitute('<\(https\?://[^>[:space:]]\+\)>', '\1', 'g')
    ->substitute('<\([^< >]\+@[^< >]\+\)>', '\1', 'g')
    # Handle links - must preserve link text, remove link syntax
    # Empty URL: [text]()
    ->substitute('\!\=\[\([^][]*\)\](\s*)', '\1', 'g')
    # URL with angle brackets and optional title: [text](<url> "title")
    ->substitute('\!\=\[\([^][]*\)\](\s*<[^>]\+>\s*\%("[^"]*"\|''[^'']*''\|(\([^)]\|\\.\)*)\)\=\s*)', '\1', 'g')
    # URL (possibly with parens) and optional title: [text](url "title")
    ->substitute('\!\=\[\([^][]*\)\](\s*[^()[:space:]]\+\%(([^()]*)[^()[:space:]]*\)*\s*\%("[^"]*"\|''[^'']*''\|(\([^)]\|\\.\)*)\)\=\s*)', '\1', 'g')
enddef

def StripComplexInlineLinks(text: string): string
  var result = text

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
# Strip inline links/images for display purposes
# Optimization: fast-path check avoids expensive regex when no links present
def StripInlineLinks(text: string): string
  var result = ResolveReferenceLinks(text)

  # Fast path: no links present
  if result !~ '!\=\[\|<https\?://\|<[^< >]\+@'
    return result
  endif

  result = StripSimpleInlineLinks(result)
  result = StripComplexInlineLinks(result)

  return result
enddef

# Preprocess inline text: strip links, detect code spans, decode HTML entities
# Optimization: fast-path check avoids GetCodeSpans when no special chars present
def PreprocessInlineText(text: string): string
  # Fast path: no special content to process
  if text !~ '!\=\[\|<\|&#\|&nbsp;\|&lt;\|&gt;\|&amp;\|&quot;\|&apos;'
    var code_spans = GetCodeSpans(text)
    if code_spans->empty()
      return text
    endif
  endif

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

    # Code spans preserve literal content (no HTML entity decoding)
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
# Returns delimiter with flanking info per GFM emphasis rules
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
    if c.IsEscaped(delimiter[0])
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
      $'^{pos_prefix}{delim_escaped}\%(\s\|$\|{c.PUNCTUATION}\)\@!\|' ..
      $'^{pos_prefix}\%(\s\|^\|{c.PUNCTUATION}\)\@1<={delim_escaped}{c.PUNCTUATION}',
      check_pos) >= 0

    # Check if delimiter can close emphasis (right-flanking)
    var is_right = text->match(
      $'^{pos_prefix}\%(\s\|^\|{c.PUNCTUATION}\)\@1<!{delim_escaped}\|' ..
      $'^{pos_prefix}{c.PUNCTUATION}\@1<={delim_escaped}\%(\s\|$\|{c.PUNCTUATION}\)',
      check_pos) >= 0

    if !is_left && !is_right
      search_pos = delimiter_run[2]
      continue
    endif

    # GFM intra-word rule: _ cannot emphasize inside words (unlike *)
    if delimiter_run[0][0] == '_'
      var preceded_by_word = delimiter_run[1] > 0 && text[delimiter_run[1] - 1] =~ '\w'
      var followed_by_word = delimiter_run[2] < text_len && text[delimiter_run[2]] =~ '\w'

      # Example: foo_bar_baz does not produce emphasis
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
  result.props->insert(c.GetMarkerProp(INLINE_PROP_TYPES[cur.marker],
    rel_pos + 1,
    result.text->len()))
  result->extend({'end_pos': cur.end[1]})

  return result
enddef

# Match right delimiter with left delimiters in sequence
# Implements GFM emphasis matching algorithm with sum rule
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

    # GFM sum rule: prevents ***text*** from mismatching when nested
    # If both delimiters can open/close and their sum is divisible by 3,
    # they don't match (unless one is also divisible by 3)
    if delimiter.left || seq[idx].right
      if (delimiter_len + seq_marker_len) % 3 == 0
	  && (delimiter_len % 3 > 0 || seq_marker_len % 3 > 0)
	idx -= 1
	continue
      endif
    endif

    # Match emphasis: use min of both delimiter lengths (max 2 for strong)
    var marker_len = min([delimiter_len, seq_marker_len, 2])

    # Split longer opener to consume only what's needed
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

    # Skip emphasis processing inside code spans
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

  # Remove unclosed delimiters (keeps only matched emphasis and code spans)
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
export def ParseInlines(text: string, rel_pos: number = 0): dict<any>
  var input_text = PreprocessInlineText(text)
  var code_spans = GetCodeSpans(input_text)

  # Find and match all emphasis delimiters
  var matches = FindEmphasisMatches(input_text, code_spans)

  # Compose final text with properties
  return ComposeFormattedText(input_text, matches, rel_pos)
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
