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
    ]
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
