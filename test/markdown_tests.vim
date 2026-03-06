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
      [{'col': 1, 'type': 'LspMarkdownThematicBreak', 'length': 240}],
	[],
      [{'col': 1, 'type': 'LspMarkdownThematicBreak', 'length': 240}],
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
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 19},
	 {'col': 5, 'type': 'LspMarkdownCode', 'length': 6}],
	[],
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 21},
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
    [
      # Inline links
      # Input text
      [
	'Visit [GitHub](https://github.com) for more info.',
	'',
	'Check [this link](https://example.com "Example Site") for details.'
      ],
      # Expected text
      [
      'Visit GitHub for more info.',
	'',
      'Check this link for details.'
      ],
      # Expected text properties
      [
	[],
	[],
	[]
      ]
    ],
    [
      # Autolinks
      # Input text
      [
	'Visit <https://github.com> or email <test@example.com>.'
      ],
      # Expected text
      [
	'Visit https://github.com or email test@example.com.'
      ],
      # Expected text properties
      [
	[{'col': 7, 'type': 'LspMarkdownLink', 'length': 18},
	 {'col': 35, 'type': 'LspMarkdownLink', 'length': 16}]
      ]
    ],
    [
      # Links with inline formatting
      # Input text
      [
	'See [**bold link**](https://example.com) and [*italic link*](https://test.com).'
      ],
      # Expected text
      [
	'See bold link and italic link.'
      ],
      # Expected text properties
      [
	[{'col': 5, 'type': 'LspMarkdownBold', 'length': 9},
	 {'col': 19, 'type': 'LspMarkdownItalic', 'length': 11}]
      ]
    ],
    [
      # Task lists (GFM extension)
      # Input text
      [
	'- [ ] Unchecked task',
	'- [x] Checked task',
	'- [X] Also checked'
      ],
      # Expected text
      [
	' - [ ] Unchecked task',
	' - [x] Checked task',
	' - [X] Also checked'
      ],
      # Expected text properties
      [
      [{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3},
       {'col': 4, 'type': 'LspMarkdownTaskMarker', 'length': 3}],
      [{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3},
       {'col': 4, 'type': 'LspMarkdownTaskMarker', 'length': 3}],
      [{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3},
       {'col': 4, 'type': 'LspMarkdownTaskMarker', 'length': 3}]
      ]
    ],
    [
      # Table with column alignment (alignment syntax preserved)
      # Input text
      [
	'| Left | Center | Right |',
	'|:-----|:------:|------:|',
	'| L1   | C1     | R1    |'
      ],
      # Expected text
      [
	' Left | Center | Right ',
	':-----|:------:|------:',
	' L1   | C1     | R1    '
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownTableHeader', 'length': 6},
	 {'col': 7, 'type': 'LspMarkdownTableMarker', 'length': 1},
	 {'col': 8, 'type': 'LspMarkdownTableHeader', 'length': 8},
	 {'col': 16, 'type': 'LspMarkdownTableMarker', 'length': 1},
	 {'col': 17, 'type': 'LspMarkdownTableHeader', 'length': 7}],
	[{'col': 1, 'type': 'LspMarkdownTableMarker', 'length': 23}],
	[{'col': 7, 'type': 'LspMarkdownTableMarker', 'length': 1},
	 {'col': 16, 'type': 'LspMarkdownTableMarker', 'length': 1}]
      ]
    ],
    [
      # HTML entities
      # Input text
      [
	'Use &lt;tag&gt; for HTML and &amp; for ampersand.',
	'Quote with &quot; and apostrophe &apos;.'
      ],
      # Expected text
      [
	"Use <tag> for HTML and & for ampersand. Quote with \" and apostrophe '."
      ],
      # Expected text properties
      [
	[]
      ]
    ],
    [
      # ATX heading with closing sequence
      # Input text
      [
	'# Heading with hash #',
	'## Multiple hashes ###',
	'### Unbalanced ####'
      ],
      # Expected text
      [
	'Heading with hash',
	'',
	'Multiple hashes',
	'',
	'Unbalanced'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 17}],
	[],
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 15}],
	[],
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 10}]
      ]
    ],
    [
      # Intra-word emphasis (paragraph joining)
      # Input text
      [
	'This is un*frigging*believable and super**great**stuff.',
	'Use under_scores_in_words without emphasis.'
      ],
      # Expected text
      [
	'This is unfriggingbelievable and supergreatstuff. Use under_scores_in_words without emphasis.'
      ],
      # Expected text properties
      [
	[{'col': 11, 'type': 'LspMarkdownItalic', 'length': 8},
	 {'col': 39, 'type': 'LspMarkdownBold', 'length': 5}]
      ]
    ],
    [
      # Ordered list starting with different numbers
      # Input text
      [
	'5. Fifth item',
	'6. Sixth item',
	'100. Hundredth item'
      ],
      # Expected text
      [
	' 5. Fifth item',
	' 6. Sixth item',
	' 100. Hundredth item'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 4}],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 4}],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 6}]
      ]
    ],
    [
      # List with multiple paragraphs
      # Input text
      [
	'- First item',
	'',
	'  Continuation of first',
	'',
	'- Second item'
      ],
      # Expected text
      [
	' - First item',
	'',
      'Continuation of first',
	'',
	' - Second item'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}],
	[],
	[],
	[],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}]
      ]
    ],
    [
      # Nested block quotes
      # Input text
      [
	'> Level 1 quote',
	'> > Level 2 nested',
	'> Back to level 1'
      ],
      # Expected text
      [
	'Level 1 quote',
	'Level 2 nested Back to level 1'
      ],
      # Expected text properties
      [
	[],
	[]
      ]
    ],
    [
      # Backslash line breaks
      # Input text
      [
	'Line with backslash\',
	'continues here'
      ],
      # Expected text
      [
	'Line with backslash',
	'continues here'
      ],
      # Expected text properties
      [
	[],
	[]
      ]
    ],
    [
      # Code fence with longer delimiter
      # Input text
      [
	'`````',
	'Code with ``` inside',
	'`````',
	'Text after'
      ],
      # Expected text
      [
	'Code with ``` inside',
	'',
	'Text after'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownCodeBlock', 'end_lnum': 1, 'end_col': 21}],
	[],
	[]
      ]
    ],
    [
      # Empty emphasis should not format
      # Input text
      [
	'Empty ** ** bold and __ __ underscore.',
	'Empty * * italic and _ _ underscore.'
      ],
      # Expected text
      [
	'Empty ** ** bold and __ __ underscore. Empty * * italic and _ _ underscore.'
      ],
      # Expected text properties
      [
	[]
      ]
    ],
    [
      # Mixed list types (loose and tight)
      # Input text
      [
	'- Tight item 1',
	'- Tight item 2',
	'',
	'- Loose item 1',
	'',
	'- Loose item 2'
      ],
      # Expected text
      [
	' - Tight item 1',
	' - Tight item 2',
	' - Loose item 1',
	' - Loose item 2'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}]
      ]
    ],
    [
      # Code span edge cases
      # Input text
      [
	'Single `backtick` here.',
	'Multiple `` backticks `` here.',
	'No closing `backtick here.'
      ],
      # Expected text
      [
	'Single backtick here. Multiple backticks here. No closing `backtick here.'
      ],
      # Expected text properties
      [
	[{'col': 8, 'type': 'LspMarkdownCode', 'length': 8},
	 {'col': 32, 'type': 'LspMarkdownCode', 'length': 9}]
      ]
    ],
    [
      # Emphasis with punctuation
      # Input text
      [
	'*Emphasis* with trailing punctuation.',
	'**Bold** text, and *italic* text.',
	'_Underscore_ emphasis!'
      ],
      # Expected text
      [
	'Emphasis with trailing punctuation. Bold text, and italic text. Underscore emphasis!'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownItalic', 'length': 8},
	 {'col': 37, 'type': 'LspMarkdownBold', 'length': 4},
	 {'col': 52, 'type': 'LspMarkdownItalic', 'length': 6},
	 {'col': 65, 'type': 'LspMarkdownItalic', 'length': 10}]
      ]
    ],
    [
      # Headings without space after hash
      # Input text
      [
	'#No space heading',
	'## Normal heading'
      ],
      # Expected text
      [
	'#No space heading',
	'',
	'Normal heading'
      ],
      # Expected text properties
      [
	[],
	[],
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 14}]
      ]
    ],
    [
      # Fenced code with info string containing backticks
      # Input text
      [
	'```lang`with`backticks',
	'code content',
	'```'
      ],
      # Expected text
      [
	'code content'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownCodeBlock', 'end_lnum': 1, 'end_col': 13}]
      ]
    ],
    [
      # List items with code blocks
      # Input text
      [
	'- List item with code:',
	'',
	'      code block',
	'',
	'- Another item'
      ],
      # Expected text
      [
	' - List item with code:',
	'',
      '  code block',
	'',
	' - Another item'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}],
	[],
      [{'col': 1, 'type': 'LspMarkdownCodeBlock', 'end_col': 13, 'end_lnum': 3}],
	[],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}]
      ]
    ],
    [
      # Setext heading underline length
      # Input text
      [
	'Heading',
	'=',
	'Another',
	'---'
      ],
      # Expected text
      [
	'Heading',
	'',
	'Another'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 7}],
	[],
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 7}]
      ]
    ],
    [
      # Zero-width spaces and special characters
      # Input text
      [
	'Text with em—dash and en–dash.',
	'Ellipsis… and bullet •.'
      ],
      # Expected text
      [
	'Text with em—dash and en–dash. Ellipsis… and bullet •.'
      ],
      # Expected text properties
      [
	[]
      ]
    ],
    [
      # Multiple consecutive blank lines
      # Input text
      [
	'First paragraph.',
	'',
	'',
	'',
	'Second paragraph.'
      ],
      # Expected text
      [
	'First paragraph.',
	'',
	'Second paragraph.'
      ],
      # Expected text properties
      [
	[], [], []
      ]
    ],
    [
      # Link in heading
      # Input text
      [
	'# Heading with [link](https://example.com)',
	'## Another [**bold link**](https://test.com)'
      ],
      # Expected text
      [
      'Heading with link',
	'',
      'Another bold link'
      ],
      # Expected text properties
      [
      [{'col': 1, 'type': 'LspMarkdownHeading', 'length': 17}],
	[],
      [{'col': 1, 'type': 'LspMarkdownHeading', 'length': 17},
       {'col': 9, 'type': 'LspMarkdownBold', 'length': 9}]
      ]
    ],
    [
      # Code block immediately after list
      # Input text
      [
	'- List item',
	'',
	'    code block',
	'    more code'
      ],
      # Expected text
      [
	' - List item',
	'',
	'code block',
	'more code'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}],
	[],
	[{'col': 1, 'type': 'LspMarkdownCodeBlock', 'end_col': 11, 'end_lnum': 4}],
	[]
      ]
    ],
    [
      # Table without outer pipes (parsed as table)
      # Input text
      [
	'Header 1 | Header 2',
	'---------|----------',
	'Cell 1   | Cell 2'
      ],
      # Expected text
      [
	'Header 1 | Header 2',
	'---------|----------',
	'Cell 1   | Cell 2'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownTableHeader', 'length': 9},
	 {'col': 10, 'type': 'LspMarkdownTableMarker', 'length': 1},
	 {'col': 11, 'type': 'LspMarkdownTableHeader', 'length': 9}],
	[{'col': 1, 'type': 'LspMarkdownTableMarker', 'length': 20}],
	[{'col': 10, 'type': 'LspMarkdownTableMarker', 'length': 1}]
      ]
    ],
    [
      # Emphasis not crossing paragraph boundaries
      # Input text
      [
	'*Start emphasis',
	'',
	'End emphasis*'
      ],
      # Expected text
      [
	'*Start emphasis',
	'',
	'End emphasis*'
      ],
      # Expected text properties
      [
	[], [], []
      ]
    ],
    [
      # Reference-style links
      # Input text
      [
	'Reference [GitHub][gh] link and [example][].',
	'',
	'[gh]: https://github.com',
	'[example]: https://example.com "Example"'
      ],
      # Expected text
      [
	'Reference GitHub link and example.'
      ],
      # Expected text properties
      [
	[]
      ]
    ],
    [
      # Images (inline and reference)
      # Input text
      [
	'Inline image ![logo](https://img.example/logo.png) here.',
	'',
	'Reference image ![banner][img].',
	'',
	'[img]: https://img.example/banner.png'
      ],
      # Expected text
      [
	'Inline image logo here.',
	'',
	'Reference image banner.'
      ],
      # Expected text properties
      [
	[],
	[],
	[]
      ]
    ],
    [
      # Heading levels 4 to 6
      # Input text
      [
	'#### Level four heading',
	'##### Level five heading',
	'###### Level six heading'
      ],
      # Expected text
      [
	'Level four heading',
	'',
	'Level five heading',
	'',
	'Level six heading'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 18}],
	[],
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 18}],
	[],
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 17}]
      ]
    ],
    [
      # Bare URL autolinks
      # Input text
      [
	'Visit https://example.com/path?q=1 and http://test.dev for details.'
      ],
      # Expected text
      [
	'Visit https://example.com/path?q=1 and http://test.dev for details.'
      ],
      # Expected text properties
      [
	[{'col': 7, 'type': 'LspMarkdownLink', 'length': 28},
	 {'col': 40, 'type': 'LspMarkdownLink', 'length': 15}]
      ]
    ],
    [
      # Numeric HTML entities
      # Input text
      [
	'Entity decimal: &#35;, hex: &#x23;, copy: &#169;.'
      ],
      # Expected text
      [
	'Entity decimal: #, hex: #, copy: ©.'
      ],
      # Expected text properties
      [
	[]
      ]
    ],
    [
      # Reference labels are case-insensitive and whitespace-normalized
      # Input text
      [
	'Use [A][foo   bar] and [B][FOO BAR].',
	'',
	'[Foo Bar]: https://example.com'
      ],
      # Expected text
      [
	'Use A and B.'
      ],
      # Expected text properties
      [
	[]
      ]
    ],
    [
      # Shortcut reference links
      # Input text
      [
	'See [Docs] for details.',
	'',
	'[Docs]: https://example.com/docs'
      ],
      # Expected text
      [
	'See Docs for details.'
      ],
      # Expected text properties
      [
	[]
      ]
    ],
    [
      # Undefined reference links remain literal
      # Input text
      [
	'Unknown [ref][missing] should stay literal.'
      ],
      # Expected text
      [
	'Unknown [ref][missing] should stay literal.'
      ],
      # Expected text properties
      [
	[]
      ]
    ],
    [
      # GFM autolink literals (www and email)
      # Input text
      [
	'Contact test@example.com and visit www.example.com.'
      ],
      # Expected text
      [
	'Contact test@example.com and visit www.example.com.'
      ],
      # Expected text properties
      [
	[{'col': 9, 'type': 'LspMarkdownLink', 'length': 16},
	 {'col': 36, 'type': 'LspMarkdownLink', 'length': 15}]
      ]
    ],
    [
      # Raw HTML block is preserved
      # Input text
      [
	'<div class="note">',
	'**not markdown** inside html block',
	'</div>'
      ],
      # Expected text
      [
	'<div class="note">',
	'**not markdown** inside html block',
	'</div>'
      ],
      # Expected text properties
      [
	[],
	[],
	[]
      ]
    ],
    [
      # Raw HTML inline with surrounding markdown
      # Input text
      [
	'Before <span>raw</span> after and *italic* text.'
      ],
      # Expected text
      [
	'Before <span>raw</span> after and italic text.'
      ],
      # Expected text properties
      [
	[{'col': 35, 'type': 'LspMarkdownItalic', 'length': 6}]
      ]
    ],
    [
      # Table escaped pipes inside cells
      # Input text
      [
	'| H1 | H2 |',
	'|----|----|',
	'| a \| b | c |'
      ],
      # Expected text
      [
	' H1 | H2 ',
	'----|----',
	' a | b | c '
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownTableHeader', 'length': 4},
	 {'col': 5, 'type': 'LspMarkdownTableMarker', 'length': 1},
	 {'col': 6, 'type': 'LspMarkdownTableHeader', 'length': 4}],
	[{'col': 1, 'type': 'LspMarkdownTableMarker', 'length': 9}],
	[{'col': 8, 'type': 'LspMarkdownTableMarker', 'length': 1}]
      ]
    ],
    [
      # Table rows with missing trailing cells
      # Input text
      [
	'| Left | Right |',
	'|------|-------|',
	'| only-left |'
      ],
      # Expected text
      [
	' Left | Right ',
	'------|-------',
	' only-left '
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownTableHeader', 'length': 6},
	 {'col': 7, 'type': 'LspMarkdownTableMarker', 'length': 1},
	 {'col': 8, 'type': 'LspMarkdownTableHeader', 'length': 7}],
      [{'col': 1, 'type': 'LspMarkdownTableMarker', 'length': 14}],
	[]
      ]
    ],
    [
      # Inline link destination with nested parentheses
      # Input text
      [
	'Check [paren](https://example.com/a(b)c) link.'
      ],
      # Expected text
      [
	'Check paren link.'
      ],
      # Expected text properties
      [
	[]
      ]
    ],
    [
      # Inline link destination in angle brackets
      # Input text
      [
	'Check [angle](<https://example.com/a(b)c>) now.'
      ],
      # Expected text
      [
	'Check angle now.'
      ],
      # Expected text properties
      [
	[]
      ]
    ],
    [
      # Unclosed fenced code block to end of document
      # Input text
      [
	'```',
	'line 1',
	'line 2'
      ],
      # Expected text
      [
	'line 1',
	'line 2'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownCodeBlock', 'end_lnum': 2, 'end_col': 7}],
	[]
      ]
    ],
    [
      # Shorter closing fence does not terminate fenced code
      # Input text
      [
	'````',
	'alpha',
	'```',
	'omega'
      ],
      # Expected text
      [
	'alpha',
	'```',
	'omega'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownCodeBlock', 'end_lnum': 3, 'end_col': 6}],
	[],
	[]
      ]
    ],
    [
      # Nested task lists
      # Input text
      [
	'- [ ] Parent task',
	'  - [x] Child done',
	'  - [ ] Child todo'
      ],
      # Expected text
      [
	' - [ ] Parent task',
	'    - [x] Child done',
	'    - [ ] Child todo'
      ],
      # Expected text properties
      [
      [{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3},
       {'col': 4, 'type': 'LspMarkdownTaskMarker', 'length': 3}],
      [{'col': 4, 'type': 'LspMarkdownListMarker', 'length': 3},
       {'col': 7, 'type': 'LspMarkdownTaskMarker', 'length': 3}],
      [{'col': 4, 'type': 'LspMarkdownListMarker', 'length': 3},
       {'col': 7, 'type': 'LspMarkdownTaskMarker', 'length': 3}]
      ]
    ],
    [
      # Raw HTML comment block is preserved
      # Input text
      [
	'<!--',
	'*not italic*',
	'-->'
      ],
      # Expected text
      [
	'<!--',
	'*not italic*',
	'-->'
      ],
      # Expected text properties
      [
	[],
	[],
	[]
      ]
    ],
    [
      # Autolink literal outside code span only
      # Input text
      [
	'`www.example.com` and www.example.com'
      ],
      # Expected text
      [
	'www.example.com and www.example.com'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownCode', 'length': 15},
	 {'col': 21, 'type': 'LspMarkdownLink', 'length': 15}]
      ]
    ],
    [
      # Collapsed reference image
      # Input text
      [
	'Look ![logo][] now.',
	'',
	'[logo]: https://img.example/logo.png'
      ],
      # Expected text
      [
	'Look logo now.'
      ],
      # Expected text properties
      [
	[]
      ]
    ],
    [
      # Reference definition with multiline title
      # Input text
      [
	'Check [site][s].',
	'',
	'[s]: https://example.com',
	'  "Example title"'
      ],
      # Expected text
      [
	'Check site.'
      ],
      # Expected text properties
      [
	[]
      ]
    ],
    [
      # Raw script HTML block is preserved
      # Input text
      [
	'<script>',
	'*not italic*',
	'const x = 1',
	'</script>'
      ],
      # Expected text
      [
	'<script>',
	'*not italic*',
	'const x = 1',
	'</script>'
      ],
      # Expected text properties
      [
	[],
	[],
	[],
	[]
      ]
    ],
    [
      # Fenced code with up to three-space indentation
      # Input text
      [
	'   ```',
	'indented fence content',
	'   ```',
	'after'
      ],
      # Expected text
      [
	'indented fence content',
	'',
	'after'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownCodeBlock', 'end_lnum': 1, 'end_col': 23}],
	[],
	[]
      ]
    ],
    [
      # Invalid table delimiter row is not parsed as table
      # Input text
      [
	'| H1 | H2 |',
	'|----|',
	'| a | b |'
      ],
      # Expected text
      [
	'| H1 | H2 | |----| | a | b |'
      ],
      # Expected text properties
      [
	[]
      ]
    ],
    [
      # ATX heading with 7 or more hashes (not a heading)
      # Input text
      [
	'####### Seven hashes',
	'######## Eight hashes'
      ],
      # Expected text
      [
	'####### Seven hashes ######## Eight hashes'
      ],
      # Expected text properties
      [
	[]
      ]
    ],
    [
      # Setext heading with 4+ space indentation (code block, not heading)
      # Input text
      [
	'    Indented text',
	'    ==='
      ],
      # Expected text
      [
	'Indented text',
	'==='
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownCodeBlock', 'end_lnum': 2, 'end_col': 14}],
	[]
      ]
    ],
    [
      # Code span with leading and trailing spaces (trimmed to single space)
      # Input text
      [
	'Text `  spaced  ` here.'
      ],
      # Expected text
      [
	'Text  spaced  here.'
      ],
      # Expected text properties
      [
	[{'col': 6, 'type': 'LspMarkdownCode', 'length': 8}]
      ]
    ],
    [
      # Code span with internal line ending
      # Input text
      [
	'Code `with',
	'newline` text.'
      ],
      # Expected text
      [
	'Code with newline text.'
      ],
      # Expected text properties
      [
	[{'col': 6, 'type': 'LspMarkdownCode', 'length': 12}]
      ]
    ],
    [
      # Emphasis with left-flanking and right-flanking delimiter rules
      # Input text
      [
	'*before* and *after*.',
	'Not*emphasized*at*all.',
	'_before_ and _after_.'
      ],
      # Expected text
      [
	'before and after. Notemphasizedat*all. before and after.'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownItalic', 'length': 6},
	 {'col': 12, 'type': 'LspMarkdownItalic', 'length': 5},
	 {'col': 22, 'type': 'LspMarkdownItalic', 'length': 10},
	 {'col': 40, 'type': 'LspMarkdownItalic', 'length': 6},
	 {'col': 51, 'type': 'LspMarkdownItalic', 'length': 5}]
      ]
    ],
    [
      # Lazy continuation in lists
      # Input text
      [
	'- First item',
	'continues here',
	'- Second item'
      ],
      # Expected text
      [
	' - First item continues here',
	' - Second item'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}]
      ]
    ],
    [
      # Fenced code block with 4+ space indentation (not a code block)
      # Input text
      [
	'    ```',
	'    content',
	'    ```'
      ],
      # Expected text
      [
	'```',
	'content',
	'```'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownCodeBlock', 'end_lnum': 3, 'end_col': 8}],
	[],
	[]
      ]
    ],
    [
      # Deeply nested block quotes
      # Input text
      [
	'> Level 1',
	'> > Level 2',
	'> > > Level 3',
	'> > Back to 2',
	'> Back to 1'
      ],
      # Expected text
      [
	'Level 1',
	'Level 2',
	'Level 3 Back to 2 Back to 1'
      ],
      # Expected text properties
      [
	[],
	[],
	[]
      ]
    ],
    [
      # Link with title in double quotes
      # Input text
      [
	'Link [here](https://example.com "Title with spaces").'
      ],
      # Expected text
      [
	'Link here.'
      ],
      # Expected text properties
      [
	[]
      ]
    ],
    [
      # Link with title in single quotes
      # Input text
      [
	'Link [here](https://example.com ''Single quote title'').'
      ],
      # Expected text
      [
	'Link here.'
      ],
      # Expected text properties
      [
	[]
      ]
    ],
    [
      # Link with title in parentheses
      # Input text
      [
	'Link [here](https://example.com (Paren title)).'
      ],
      # Expected text
      [
	'Link here.'
      ],
      # Expected text properties
      [
	[]
      ]
    ],
    [
      # Empty link text
      # Input text
      [
	'Empty [](https://example.com) link.'
      ],
      # Expected text
      [
	'Empty  link.'
      ],
      # Expected text properties
      [
	[]
      ]
    ],
    [
      # Emphasis delimiter run with mixed content
      # Input text
      [
	'**bold _nested italic_ end**'
      ],
      # Expected text
      [
	'bold nested italic end'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownBold', 'length': 22},
	 {'col': 6, 'type': 'LspMarkdownItalic', 'length': 13}]
      ]
    ],
    [
      # List item with lazy continuation and code span
      # Input text
      [
	'- Item with `code`',
	'continues here'
      ],
      # Expected text
      [
	' - Item with code continues here'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3},
	 {'col': 14, 'type': 'LspMarkdownCode', 'length': 4}]
      ]
    ],
    [
      # List starting at arbitrary number (maintains number)
      # Input text
      [
	'7. Seventh',
	'8. Eighth',
	'9. Ninth'
      ],
      # Expected text
      [
	' 7. Seventh',
	' 8. Eighth',
	' 9. Ninth'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 4}],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 4}],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 4}]
      ]
    ],
    [
      # List with multiple blank lines between items
      # Input text
      [
	'- First item',
	'',
	'',
	'- Second item'
      ],
      # Expected text
      [
	' - First item',
	' - Second item'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}]
      ]
    ],
    [
      # Nested emphasis with different markers
      # Input text
      [
	'***bold and italic*** vs **bold with *italic* inside**'
      ],
      # Expected text
      [
	'bold and italic vs bold with italic inside'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownItalic', 'length': 15},
	 {'col': 1, 'type': 'LspMarkdownBold', 'length': 15},
	 {'col': 20, 'type': 'LspMarkdownBold', 'length': 23},
	 {'col': 30, 'type': 'LspMarkdownItalic', 'length': 6}]
      ]
    ],
    [
      # Code block with mixed indentation
      # Input text
      [
	'    line 1',
	'      line 2 indented',
	'    line 3'
      ],
      # Expected text
      [
	'line 1',
	'  line 2 indented',
	'line 3'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownCodeBlock', 'end_lnum': 3, 'end_col': 18}],
	[],
	[]
      ]
    ],
    [
      # Table with empty cells
      # Input text
      [
	'| A | B | C |',
	'|---|---|---|',
	'| 1 |   | 3 |',
	'|   | 2 |   |'
      ],
      # Expected text
      [
	' A | B | C ',
	'---|---|---',
	' 1 |   | 3 ',
	'   | 2 |   '
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownTableHeader', 'length': 3},
	 {'col': 4, 'type': 'LspMarkdownTableMarker', 'length': 1},
	 {'col': 5, 'type': 'LspMarkdownTableHeader', 'length': 3},
	 {'col': 8, 'type': 'LspMarkdownTableMarker', 'length': 1},
	 {'col': 9, 'type': 'LspMarkdownTableHeader', 'length': 3}],
	[{'col': 1, 'type': 'LspMarkdownTableMarker', 'length': 11}],
	[{'col': 4, 'type': 'LspMarkdownTableMarker', 'length': 1},
	 {'col': 8, 'type': 'LspMarkdownTableMarker', 'length': 1}],
	[{'col': 4, 'type': 'LspMarkdownTableMarker', 'length': 1},
	 {'col': 8, 'type': 'LspMarkdownTableMarker', 'length': 1}]
      ]
    ],
    [
      # Setext heading interrupted by thematic break
      # Input text
      [
	'Heading text',
	'---'
      ],
      # Expected text
      [
	'Heading text'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 12}]
      ]
    ],
    [
      # Block quote with multiple paragraphs
      # Input text
      [
	'> First paragraph in quote.',
	'>',
	'> Second paragraph in quote.'
      ],
      # Expected text
      [
	'First paragraph in quote.',
	'Second paragraph in quote.'
      ],
      # Expected text properties
      [
	[],
	[]
      ]
    ],
    [
      # Emphasis immediately before/after punctuation
      # Input text
      [
	'(*italic*) and [**bold**] and {_underscore_}.'
      ],
      # Expected text
      [
	'(italic) and [bold] and {underscore}.'
      ],
      # Expected text properties
      [
	[{'col': 2, 'type': 'LspMarkdownItalic', 'length': 6},
	 {'col': 15, 'type': 'LspMarkdownBold', 'length': 4},
	 {'col': 26, 'type': 'LspMarkdownItalic', 'length': 10}]
      ]
    ],
    [
      # List with deeply nested items (3+ levels)
      # Input text
      [
	'- Level 1',
	'  - Level 2',
	'    - Level 3',
	'      - Level 4'
      ],
      # Expected text
      [
	' - Level 1',
	'    - Level 2',
	'       - Level 3',
	'          - Level 4'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}],
	[{'col': 4, 'type': 'LspMarkdownListMarker', 'length': 3}],
	[{'col': 7, 'type': 'LspMarkdownListMarker', 'length': 3}],
	[{'col': 10, 'type': 'LspMarkdownListMarker', 'length': 3}]
      ]
    ],
    [
      # HTML entity in code span (preserved)
      # Input text
      [
	'Code `&lt;tag&gt;` and normal &lt;tag&gt;.'
      ],
      # Expected text
      [
	'Code &lt;tag&gt; and normal <tag>.'
      ],
      # Expected text properties
      [
	[{'col': 6, 'type': 'LspMarkdownCode', 'length': 11}]
      ]
    ],
    [
      # Fenced code with info string and attributes
      # Input text
      [
	'```javascript {.highlight}',
	'console.log("test");',
	'```'
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
      # Mixed ordered and unordered lists
      # Input text
      [
	'1. Ordered item',
	'2. Second ordered',
	'- Unordered item',
	'- Another unordered'
      ],
      # Expected text
      [
	' 1. Ordered item',
	' 2. Second ordered',
	' - Unordered item',
	' - Another unordered'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 4}],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 4}],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}]
      ]
    ],
    [
      # Strikethrough with bold and italic
      # Input text
      [
	'~~**bold strike**~~ and ~~*italic strike*~~'
      ],
      # Expected text
      [
	'bold strike and italic strike'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownStrikeThrough', 'length': 11},
	 {'col': 1, 'type': 'LspMarkdownBold', 'length': 11},
	 {'col': 17, 'type': 'LspMarkdownStrikeThrough', 'length': 13},
	 {'col': 17, 'type': 'LspMarkdownItalic', 'length': 13}]
      ]
    ],
    [
      # Link with empty URL
      # Input text
      [
	'Link [text]() is empty.'
      ],
      # Expected text
      [
	'Link text is empty.'
      ],
      # Expected text properties
      [
	[]
      ]
    ],
    [
      # Code fence with tilde and language having special chars
      # Input text
      [
	'~~~c++',
	'int main() { }',
	'~~~'
      ],
      # Expected text
      [
	'int main() { }'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownCodeBlock', 'end_lnum': 1, 'end_col': 15}]
      ]
    ],
    [
      # ATX heading with only hashes (no space, no content)
      # Input text
      [
	'###'
      ],
      # Expected text
      [
	''
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 0}]
      ]
    ],
    [
      # List item with paragraph and indented code
      # Input text
      [
	'- List item paragraph',
	'',
	'      indented code in list',
	'',
	'- Next item'
      ],
      # Expected text
      [
	' - List item paragraph',
	'',
	'  indented code in list',
	'',
	' - Next item'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}],
	[],
	[{'col': 1, 'type': 'LspMarkdownCodeBlock', 'end_lnum': 3, 'end_col': 24}],
	[],
	[{'col': 1, 'type': 'LspMarkdownListMarker', 'length': 3}]
      ]
    ],
    [
      # Hard line break at end of heading (ignored)
      # Input text
      [
	'# Heading with break  ',
	'Next paragraph'
      ],
      # Expected text
      [
	'Heading with break',
	'',
	'Next paragraph'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownHeading', 'length': 18}],
	[],
	[]
      ]
    ],
    [
      # Thematic break with mixed markers (not valid)
      # Input text
      [
	'Before',
	'*-*',
	'After'
      ],
      # Expected text
      [
	'Before *-* After'
      ],
      # Expected text properties
      [
	[]
      ]
    ],
    [
      # Code span at start and end of line
      # Input text
      [
	'`start` middle `end`'
      ],
      # Expected text
      [
	'start middle end'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownCode', 'length': 5},
	 {'col': 14, 'type': 'LspMarkdownCode', 'length': 3}]
      ]
    ],
    [
      # Reference link with complex label
      # Input text
      [
	'See [label with **bold**][ref].',
	'',
	'[ref]: https://example.com'
      ],
      # Expected text
      [
	'See label with bold.'
      ],
      # Expected text properties
      [
	[{'col': 16, 'type': 'LspMarkdownBold', 'length': 4}]
      ]
    ],
    [
      # Double emphasis with underscore and asterisk
      # Input text
      [
	'_italic_ and **bold** and **_both_**'
      ],
      # Expected text
      [
	'italic and bold and both'
      ],
      # Expected text properties
      [
	[{'col': 1, 'type': 'LspMarkdownItalic', 'length': 6},
	 {'col': 12, 'type': 'LspMarkdownBold', 'length': 4},
	 {'col': 21, 'type': 'LspMarkdownBold', 'length': 4},
	 {'col': 21, 'type': 'LspMarkdownItalic', 'length': 4}]
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
