vim9script

# LSP semantic highlighting functions

import './offset.vim'
import './options.vim' as opt
import './buffer.vim' as buf

# Map token type names to higlight group/text property type names
var TokenTypeMap: dict<string> = {
  'namespace': 'LspSemanticNamespace',
  'type': 'LspSemanticType',
  'class': 'LspSemanticClass',
  'enum': 'LspSemanticEnum',
  'interface': 'LspSemanticInterface',
  'struct': 'LspSemanticStruct',
  'typeParameter': 'LspSemanticTypeParameter',
  'parameter': 'LspSemanticParameter',
  'variable': 'LspSemanticVariable',
  'property': 'LspSemanticProperty',
  'enumMember': 'LspSemanticEnumMember',
  'event': 'LspSemanticEvent',
  'function': 'LspSemanticFunction',
  'method': 'LspSemanticMethod',
  'macro': 'LspSemanticMacro',
  'keyword': 'LspSemanticKeyword',
  'modifier': 'LspSemanticModifier',
  'comment': 'LspSemanticComment',
  'string': 'LspSemanticString',
  'number': 'LspSemanticNumber',
  'regexp': 'LspSemanticRegexp',
  'operator': 'LspSemanticOperator',
  'decorator': 'LspSemanticDecorator'
}

export def InitOnce()
  # Define the default semantic token type highlight groups
  hlset([
    {name: 'LspSemanticNamespace', default: true, linksto: 'Type'},
    {name: 'LspSemanticType', default: true, linksto: 'Type'},
    {name: 'LspSemanticClass', default: true, linksto: 'Type'},
    {name: 'LspSemanticEnum', default: true, linksto: 'Type'},
    {name: 'LspSemanticInterface', default: true, linksto: 'TypeDef'},
    {name: 'LspSemanticStruct', default: true, linksto: 'Type'},
    {name: 'LspSemanticTypeParameter', default: true, linksto: 'Type'},
    {name: 'LspSemanticParameter', default: true, linksto: 'Identifier'},
    {name: 'LspSemanticVariable', default: true, linksto: 'Identifier'},
    {name: 'LspSemanticProperty', default: true, linksto: 'Identifier'},
    {name: 'LspSemanticEnumMember', default: true, linksto: 'Constant'},
    {name: 'LspSemanticEvent', default: true, linksto: 'Identifier'},
    {name: 'LspSemanticFunction', default: true, linksto: 'Function'},
    {name: 'LspSemanticMethod', default: true, linksto: 'Function'},
    {name: 'LspSemanticMacro', default: true, linksto: 'Macro'},
    {name: 'LspSemanticKeyword', default: true, linksto: 'Keyword'},
    {name: 'LspSemanticModifier', default: true, linksto: 'Type'},
    {name: 'LspSemanticComment', default: true, linksto: 'Comment'},
    {name: 'LspSemanticString', default: true, linksto: 'String'},
    {name: 'LspSemanticNumber', default: true, linksto: 'Number'},
    {name: 'LspSemanticRegexp', default: true, linksto: 'String'},
    {name: 'LspSemanticOperator', default: true, linksto: 'Operator'},
    {name: 'LspSemanticDecorator', default: true, linksto: 'Macro'}
  ])

  for hlName in TokenTypeMap->values()
    prop_type_add(hlName, {highlight: hlName, combine: true})
  endfor
enddef

def ParseSemanticTokenMods(lspserverTokenMods: list<string>, tokenMods: number): string
  var n = tokenMods
  var tokenMod: number
  var str = ''

  while n > 0
    tokenMod = float2nr(log10(and(n, invert(n - 1))) / log10(2))
    str = $'{str}{lspserverTokenMods[tokenMod]},'
    n = and(n, n - 1)
  endwhile

  return str
enddef

# Apply the edit operations in a semantic tokens delta update message
# (SemanticTokensDelta) from the language server.
#
# The previous list of tokens are stored in the buffer-local
# LspSemanticTokensData variable.  After applying the edits in
# semTokens.edits, the new set of tokens are returned in semTokens.data.
def ApplySemanticTokenEdits(bnr: number, semTokens: dict<any>)
  if semTokens.edits->empty()
    return
  endif

  # Need to sort the edits and apply the last edit first.
  semTokens.edits->sort((a: dict<any>, b: dict<any>) => a.start - b.start)

  # TODO: Remove this code
  # var d = bnr->getbufvar('LspSemanticTokensData', [])
  # for e in semTokens.edits
  #   var insertData = e->get('data', [])
  #   d = (e.start > 0 ? d[: e.start - 1] : []) + insertData +
  #     					d[e.start + e.deleteCount :]
  # endfor
  # semTokens.data = d

  var oldTokens = bnr->getbufvar('LspSemanticTokensData', [])
  var newTokens = []
  var idx = 0
  for e in semTokens.edits
    if e.start > 0
      newTokens->extend(oldTokens[idx : e.start - 1])
    endif
    newTokens->extend(e->get('data', []))
    idx = e.start + e.deleteCount
  endfor
  newTokens->extend(oldTokens[idx : ])
  semTokens.data = newTokens
enddef

# Process a list of semantic tokens and return the corresponding text
# properties for highlighting.
def ProcessSemanticTokens(lspserver: dict<any>, bnr: number, tokens: list<number>): dict<list<list<number>>>
  var props: dict<list<list<number>>> = {}
  var tokenLine: number = 0
  var startChar: number = 0
  var length: number = 0
  var tokenType: number = 0
  var tokenMods: number = 0
  var prevTokenLine = 0
  var lnum = 1
  var charIdx = 0

  var lspserverTokenTypes: list<string> =
				lspserver.semanticTokensLegend.tokenTypes
  var lspserverTokenMods: list<string> =
				lspserver.semanticTokensLegend.tokenModifiers

  # Each semantic token uses 5 items in the tokens List
  var i = 0
  while i < tokens->len()
    tokenLine = tokens[i]
    # tokenLine is relative to the previous token line number
    lnum += tokenLine
    if prevTokenLine != lnum
      # this token is on a different line from the previous token
      charIdx = 0
      prevTokenLine = lnum
    endif
    startChar = tokens[i + 1]
    charIdx += startChar
    length = tokens[i + 2]
    tokenType = tokens[i + 3]
    tokenMods = tokens[i + 4]

    var typeStr = lspserverTokenTypes[tokenType]
    var modStr = ParseSemanticTokenMods(lspserverTokenMods, tokenMods)

    # Decode the semantic token line number, column number and length to
    # UTF-32 encoding.
    var r = {
      start: {
	line: lnum - 1,
	character: charIdx
      },
      end: {
	line: lnum - 1,
	character: charIdx + length
      }
    }
    offset.DecodeRange(lspserver, bnr, r)

    if !props->has_key(typeStr)
      props[typeStr] = []
    endif
    props[typeStr]->add([
	lnum, r.start.character + 1,
	lnum, r.end.character + 1
      ])

    i += 5
  endwhile

  return props
enddef

# Parse the semantic highlight reply from the language server and update the
# text properties
export def UpdateTokens(lspserver: dict<any>, bnr: number, semTokens: dict<any>)

  if semTokens->has_key('edits')
    # Delta semantic update.  Need to sort the edits and apply the last edit
    # first.
    ApplySemanticTokenEdits(bnr, semTokens)
  endif

  # Cache the semantic tokens in a buffer-local variable, it will be used
  # later for a delta update.
  setbufvar(bnr, 'LspSemanticResultId', semTokens->get('resultId', ''))
  if !semTokens->has_key('data')
    return
  endif
  setbufvar(bnr, 'LspSemanticTokensData', semTokens.data)

  var props: dict<list<list<number>>>
  props = ProcessSemanticTokens(lspserver, bnr, semTokens.data)

  # First clear all the previous text properties
  if has('patch-9.0.0233')
    prop_remove({types: TokenTypeMap->values(), bufnr: bnr, all: true})
  else
    for propName in TokenTypeMap->values()
      prop_remove({type: propName, bufnr: bnr, all: true})
    endfor
  endif

  if props->empty()
    return
  endif

  # Apply the new text properties
  for tokenType in TokenTypeMap->keys()
    if props->has_key(tokenType)
      prop_add_list({bufnr: bnr, type: TokenTypeMap[tokenType]},
	props[tokenType])
    endif
  endfor
enddef

# Update the semantic highlighting for buffer "bnr"
def LspUpdateSemanticHighlight(bnr: number)
  var lspserver: dict<any> = buf.BufLspServerGet(bnr, 'semanticTokens')
  if lspserver->empty()
    return
  endif

  lspserver.semanticHighlightUpdate(bnr)
enddef

# Initialize the semantic highlighting for the buffer 'bnr'
export def BufferInit(lspserver: dict<any>, bnr: number)
  if !opt.lspOptions.semanticHighlight || !lspserver.isSemanticTokensProvider
    # no support for semantic highlighting
    return
  endif

  # Highlight all the semantic tokens
  LspUpdateSemanticHighlight(bnr)

  # buffer-local autocmds for semantic highlighting
  var acmds: list<dict<any>> = []

  acmds->add({bufnr: bnr,
	      event: 'TextChanged',
	      group: 'LSPBufferAutocmds',
	      cmd: $'LspUpdateSemanticHighlight({bnr})'})
  acmds->add({bufnr: bnr,
	      event: 'BufUnload',
	      group: 'LSPBufferAutocmds',
	      cmd: $"b:LspSemanticTokensData = [] | b:LspSemanticResultId = ''"})

  autocmd_add(acmds)
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
