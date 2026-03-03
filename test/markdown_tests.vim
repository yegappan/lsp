vim9script

# Unit tests for the Github Flavored Markdown parser

import '../autoload/lsp/markdown.vim' as md

# Test for different markdowns
def g:Test_Markdown()
  var tests: list<list<list<any>>> = [
    [
      # Different headings
      # Input text
      [
	'# First level heading',
	'## Second level heading',
	'### Third level heading',
	'#  	  Heading with leading and trailing whitespaces  	   ',
	'Multiline setext heading  ',
	'of level 1',
	'===',
	'Multiline setext heading\',
	'of level 2',
	'---'
      ],
      # Expected text
      [
	'First level heading',
	'',
	'Second level heading',
	'',
	'Third level heading',
	'',
	'Heading with leading and trailing whitespaces',
	'',
	'Multiline setext heading',
	'of level 1',
	'',
	'Multiline setext heading',
	'of level 2'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 19}],
	[],
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 20}],
	[],
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 19}],
	[],
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 45}],
	[],
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 24}],
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 10}],
	[],
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 24}],
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 10}],
      ]
    ],
    [
      # Bold text style
      # Input text
      [
	'This **word** should be bold',
	'',
	'**This line should be bold**',
	'',
	'This __word__ should be bold',
	'',
	'__This line should be bold__'
      ],
      # Expected text
      [
	'This word should be bold',
	'',
	'This line should be bold',
	'',
	'This word should be bold',
	'',
	'This line should be bold'
      ],
      # Expected text properties
      [
	[{'col': 6, 'type': 'LspMarkdownBold', 'length': 4}],
	[],
	[{'col': 1, 'type': 'LspMarkdownBold', 'length': 24}],
	[],
	[{'col': 6, 'type': 'LspMarkdownBold', 'length': 4}],
	[],
	[{'col': 1, 'type': 'LspMarkdownBold', 'length': 24}]
      ]
    ],
    [
      # Italic text style
      # Input text
      [
	'This *word* should be italic',
	'',
	'*This line should be italic*',
	'',
	'This _word_ should be italic',
	'',
	'_This line should be italic_'
      ],
      # Expected text
      [
	'This word should be italic',
	'',
	'This line should be italic',
	'',
	'This word should be italic',
	'',
	'This line should be italic'
      ],
      # Expected text properties
      [
	[{'col': 6, 'type': 'LspMarkdownItalic', 'length': 4}],
	[],
	[{'col': 1, 'type': 'LspMarkdownItalic', 'length': 26}],
	[],
	[{'col': 6, 'type': 'LspMarkdownItalic', 'length': 4}],
	[],
	[{'col': 1, 'type': 'LspMarkdownItalic', 'length': 26}]
      ],
    ],
    [
      # strikethrough text style
      # Input text
      [
	'This ~word~ should be strikethrough',
	'',
	'~This line should be strikethrough~'
      ],
      # Expected text
      [
	'This word should be strikethrough',
	'',
	'This line should be strikethrough'
      ],
      # Expected text properties
      [
	[{'col': 6, 'type': 'LspMarkdownStrikeThrough', 'length': 4}],
	[],
	[{'col': 1, 'type': 'LspMarkdownStrikeThrough', 'length': 33}]
      ]
    ],
    [
      # bold and nested italic text style
      # Input text
      [
	'**This _word_ should be bold and italic**',
      ],
      # Expected text
      [
	'This word should be bold and italic',
      ],
      # Expected text properties
      [
	[
	  {'col': 1, 'type': 'LspMarkdownBold', 'length': 35},
	  {'col': 6, 'type': 'LspMarkdownItalic', 'length': 4}
	]
      ]
    ],
    [
      # all bold and italic text style
      # Input text
      [
	'***This line should be all bold and italic***',
      ],
      # Expected text
      [
	'This line should be all bold and italic',
      ],
      # Expected text properties
      [
	[
	  {'col': 1, 'type': 'LspMarkdownItalic', 'length': 39},
	  {'col': 1, 'type': 'LspMarkdownBold', 'length': 39}
	]
      ]
    ],
    [
      # quoted text
      # FIXME: The text is not quoted
      # Input text
      [
	'Text that is not quoted',
	'> quoted text'
      ],
      # Expected text
      [
	'Text that is not quoted',
	'',
	'quoted text'
      ],
      # Expected text properties
      [
	[], [], []
      ]
    ],
    [
      # line breaks
      # Input text
      [
	'This paragraph contains ',
	'a soft line break',
	'',
	'This paragraph contains  ',
	'an hard line break',
	'',
	'This paragraph contains an emphasis _before_\',
	'an hard line break',
	'',
	'This paragraph contains an emphasis  ',
	'_after_ an hard line break',
	'',
	'This paragraph _contains\',
	'an emphasis_ with an hard line break in the middle',
	'',
	'→ This paragraph contains an hard line break  ',
	'and starts with the multibyte character "\u2192"',
	'',
	'Line breaks `',
	'do\',
	'not  ',
	'occur',
	'` inside code spans'
      ],
      # Expected text
      [
	'This paragraph contains a soft line break',
	'',
	'This paragraph contains',
	'an hard line break',
	'',
	'This paragraph contains an emphasis before',
	'an hard line break',
	'',
	'This paragraph contains an emphasis',
	'after an hard line break',
	'',
	'This paragraph contains',
	'an emphasis with an hard line break in the middle',
	'',
	'→ This paragraph contains an hard line break',
	'and starts with the multibyte character "\u2192"',
	'',
	'Line breaks do\ not   occur inside code spans'
      ],
      # Expected text properties
      [
	[],
	[],
	[],
	[],
	[],
	[{'col': 37, 'type': 'LspMarkdownItalic', 'length': 6}],
	[],
	[],
	[],
	[{'col': 1, 'type': 'LspMarkdownItalic', 'length': 5}],
	[],
	[{'col': 16, 'type': 'LspMarkdownItalic', 'length': 8}],
	[{'col': 1, 'type': 'LspMarkdownItalic', 'length': 11}],
	[],
	[],
	[],
	[],
	[{'col': 13, 'type': 'LspMarkdownCode', 'length': 15}]
      ]
    ],
    [
      # non-breaking space characters
      # Input text
      [
	'&nbsp;&nbsp;This is text.',
      ],
      # Expected text
      [
	'  This is text.',
      ],
      # Expected text properties
      [
	[]
      ]
    ],
    [
      # Fenced code block with backticks (unrecognized language)
      # Input text
      [
	'```unknownlang',
	'def hello():',
	'    return "world"',
	'```',
	'Text after code'
      ],
      # Expected text
      [
	'def hello():',
	'    return "world"',
	'',
	'Text after code'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownCodeBlock', 'end_lnum': 2, 'end_col': 19}],
	[],
	[],
	[]
      ]
    ],
    [
      # Fenced code block with tildes (unrecognized language)
      # Input text
      [
	'~~~unknownlang',
	'console.log("test");',
	'~~~'
      ],
      # Expected text
      [
	'console.log("test");'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownCodeBlock', 'end_lnum': 1, 'end_col': 21}]
      ]
    ],
    [
      # Indented code block
      # Input text
      [
	'    code line 1',
	'    code line 2',
	'    code line 3'
      ],
      # Expected text
      [
	'code line 1',
	'code line 2',
	'code line 3'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownCodeBlock', 'end_lnum': 3, 'end_col': 12}],
	[],
	[]
      ]
    ],
    [
      # Unordered list with dash
      # Input text
      [
	'- First item',
	'- Second item',
	'- Third item'
      ],
      # Expected text
      [
	' - First item',
	' - Second item',
	' - Third item'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}]
      ]
    ],
    [
      # Unordered list with asterisk and plus
      # Input text
      [
	'* Item one',
	'+ Item two'
      ],
      # Expected text
      [
	' * Item one',
	' + Item two'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}]
      ]
    ],
    [
      # Ordered list
      # Input text
      [
	'1. First item',
	'2. Second item',
	'10. Tenth item'
      ],
      # Expected text
      [
	' 1. First item',
	' 2. Second item',
	' 10. Tenth item'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 4}],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 4}],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 5}]
      ]
    ],
    [
      # List with inline formatting
      # Input text
      [
	'- Item with **bold** text',
	'- Item with `code` text',
	'1. Numbered with *italic* text'
      ],
      # Expected text
      [
	' - Item with bold text',
	' - Item with code text',
	' 1. Numbered with italic text'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3},
	 {'col': 14, 'type': 'LspMarkdownBold', 'length': 4}],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3},
	 {'col': 14, 'type': 'LspMarkdownCode', 'length': 4}],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 4},
	 {'col': 19, 'type': 'LspMarkdownItalic', 'length': 6}]
      ]
    ],
    [
      # Nested list
      # Input text
      [
	'- Parent item',
	'  - Child item 1',
	'  - Child item 2',
	'- Another parent'
      ],
      # Expected text
      [
	' - Parent item',
	'    - Child item 1',
	'    - Child item 2',
	' - Another parent'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}],
	[{'col': 4, 'type': 'LspMarkdownListMarker', 'length': 3}],
	[{'col': 4, 'type': 'LspMarkdownListMarker', 'length': 3}],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}]
      ]
    ],
    [
      # Thematic breaks (horizontal rules)
      # Input text
      [
	'Before',
	'---',
	'After first',
	'***',
	'After second',
	'___',
	'After third'
      ],
      # Expected text
      [
	'Before',
	'',
	'After first',
	"\u2500"->repeat(80),
	'After second',
	"\u2500"->repeat(80),
	'After third'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 6}],
	[],
	[],
	[],
	[],
	[],
	[]
      ]
    ],
    [
      # Table with headers and cells
      # Input text
      [
	'| Header 1 | Header 2 |',
	'|----------|----------|',
	'| Cell 1   | Cell 2   |',
	'| Cell 3   | Cell 4   |'
      ],
      # Expected text
      [
	' Header 1 | Header 2 ',
	'----------|----------',
	' Cell 1   | Cell 2   ',
	' Cell 3   | Cell 4   '
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownTableHeader', 'length': 10},
	 {'col': 11, 'type': 'LspMarkdownTableMarker', 'length': 1},
	 {'col': 12, 'type': 'LspMarkdownTableHeader', 'length': 10}],
	[{'col': 1, 'type': 'LspMarkdownTableMarker', 'length': 21}],
	[{'col': 11, 'type': 'LspMarkdownTableMarker', 'length': 1}],
	[{'col': 11, 'type': 'LspMarkdownTableMarker', 'length': 1}]
      ]
    ],
    [
      # Table with inline formatting
      # Input text
      [
	'| **Bold** | `Code` |',
	'|----------|--------|',
	'| *Italic* | Normal |'
      ],
      # Expected text
      [
	' Bold | Code ',
	'----------|--------',
	' Italic | Normal '
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownTableHeader', 'length': 6},
	 {'col': 2, 'type': 'LspMarkdownBold', 'length': 4},
	 {'col': 7, 'type': 'LspMarkdownTableMarker', 'length': 1},
	 {'col': 8, 'type': 'LspMarkdownTableHeader', 'length': 6},
	 {'col': 9, 'type': 'LspMarkdownCode', 'length': 4}],
	[{'col': 1, 'type': 'LspMarkdownTableMarker', 'length': 19}],
	[{'col': 2, 'type': 'LspMarkdownItalic', 'length': 6},
	 {'col': 9, 'type': 'LspMarkdownTableMarker', 'length': 1}]
      ]
    ],
    [
      # Code span with backticks inside
      # Input text
      [
	'Use ``code with `backticks` inside`` here'
      ],
      # Expected text
      [
	'Use code with `backticks` inside here'
      ],
      # Expected text properties
      [
	[{'col': 5, 'type': 'LspMarkdownCode', 'length': 28}]
      ]
    ],
    [
      # Mixed inline code and emphasis
      # Input text
      [
	'The `getValue()` function returns *important* data'
      ],
      # Expected text
      [
	'The getValue() function returns important data'
      ],
      # Expected text properties
      [
	[{'col': 5, 'type': 'LspMarkdownCode', 'length': 10},
	 {'col': 33, 'type': 'LspMarkdownItalic', 'length': 9}]
      ]
    ],
    [
      # Escaped characters
      # Input text
      [
	'Escaped \*asterisk\* and \_underscore\_',
	'Escaped \`backtick\` here'
      ],
      # Expected text
      [
	'Escaped *asterisk* and _underscore_ Escaped `backtick` here'
      ],
      # Expected text properties
      [
	[]
      ]
    ],
    [
      # Complex LSP hover documentation
      # Input text
      [
	'```unknownlang',
	'function calculate(x: number): number',
	'```',
	'',
	'Calculates a value.',
	'',
	'**Parameters:**',
	'',
	'- `x` - The input number',
	'',
	'**Returns:** The calculated `number`'
      ],
      # Expected text
      [
	'function calculate(x: number): number',
	'',
	'Calculates a value.',
	'',
	'Parameters:',
	'',
	' - x - The input number',
	'',
	'Returns: The calculated number'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownCodeBlock', 'end_lnum': 1, 'end_col': 38}],
	[],
	[],
	[],
	[{'col': 1, 'type': 'LspMarkdownBold', 'length': 11}],
	[],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3},
	 {'col': 4, 'type': 'LspMarkdownCode', 'length': 1}],
	[],
	[{'col': 1, 'type': 'LspMarkdownBold', 'length': 8},
	 {'col': 25, 'type': 'LspMarkdownCode', 'length': 6}]
      ]
    ],
    [
      # Block quote
      # Input text
      [
	'> This is quoted',
	'> **Bold** in quote',
	'> `code` in quote'
      ],
      # Expected text
      [
	'This is quoted Bold in quote code in quote'
      ],
      # Expected text properties
      [
	[{'col': 16, 'type': 'LspMarkdownBold', 'length': 4},
	 {'col': 30, 'type': 'LspMarkdownCode', 'length': 4}]
      ]
    ],
    [
      # Multiple paragraphs
      # Input text
      [
	'First paragraph.',
	'Continues here.',
	'',
	'Second paragraph.',
	'',
	'Third paragraph.'
      ],
      # Expected text
      [
	'First paragraph. Continues here.',
	'',
	'Second paragraph.',
	'',
	'Third paragraph.'
      ],
      # Expected text properties
      [
	[], [], [], [], []
      ]
    ],
    [
      # Heading with inline code
      # Input text
      [
	'# The `main()` function',
	'## Using **bold** in heading'
      ],
      # Expected text
      [
	'The main() function',
	'',
	'Using bold in heading'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 21},
	 {'col': 5, 'type': 'LspMarkdownCode', 'length': 6}],
	[],
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 25},
	 {'col': 7, 'type': 'LspMarkdownBold', 'length': 4}]
      ]
    ],
    [
      # Emphasis precedence test
      # Input text
      [
	'***bold and italic***',
	'**_bold and italic_**',
	'*__bold and italic__*'
      ],
      # Expected text
      [
	'bold and italic  **bold and italic bold and italic'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownItalic', 'length': 16},
	 {'col': 1, 'type': 'LspMarkdownBold', 'length': 15},
	 {'col': 16, 'type': 'LspMarkdownBold', 'length': 1},
	 {'col': 20, 'type': 'LspMarkdownItalic', 'length': 15},
	 {'col': 35, 'type': 'LspMarkdownItalic', 'length': 16},
	 {'col': 35, 'type': 'LspMarkdownItalic', 'length': 1},
	 {'col': 36, 'type': 'LspMarkdownBold', 'length': 15}]
      ]
    ],
    [
      # Ordered list with parenthesis delimiter
      # Input text
      [
	'1) First',
	'2) Second',
	'10) Tenth'
      ],
      # Expected text
      [
	' 1) First',
	' 2) Second',
	' 10) Tenth'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 4}],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 4}],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 5}]
      ]
    ],
    [
      # Strikethrough with double tilde
      # Input text
      [
	'This ~~text~~ is struck',
	'~~Entire line struck~~'
      ],
      # Expected text
      [
	'This text is struck Entire line struck'
      ],
      # Expected text properties
      [
	[{'col': 6, 'type': 'LspMarkdownStrikeThrough', 'length': 4},
	 {'col': 21, 'type': 'LspMarkdownStrikeThrough', 'length': 18}]
      ]
    ],
    [
      # Empty lines in code block
      # Input text
      [
	'    code line 1',
	'',
	'    code line 2'
      ],
      # Expected text
      [
	'code line 1',
	'',
	'code line 2'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownCodeBlock', 'end_lnum': 3, 'end_col': 12}],
	[],
	[]
      ]
    ],
    [
      # Heading with trailing spaces
      # Input text
      [
	'#  Heading with spaces  ',
	'##   Another one   '
      ],
      # Expected text
      [
	'Heading with spaces',
	'',
	'Another one'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 19}],
	[],
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 11}]
      ]
    ],
  ]

  var doc: dict<list<any>>
  var text_result: list<string>
  var props_result: list<list<dict<any>>>
  for t in tests
    doc = md.ParseMarkdown(t[0])
    text_result = doc.content->deepcopy()->map((_, v) => v.text)
    props_result = doc.content->deepcopy()->map((_, v) => v.props)
    assert_equal(t[1], text_result, t[0]->string())
    assert_equal(t[2], props_result, t[0]->string())
  endfor
enddef

# Only here to because the test runner needs it
def g:StartLangServer(): bool
  return true
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
