vim9script

# LSP plugin options
# User can override these by calling the OptionsSet() function.
export var lspOptions: dict<any> = {
  # In insert mode, complete the current symbol automatically
  # Otherwise, use omni-completion
  autoComplete: true,
  # In normal mode, highlight the current symbol automatically
  autoHighlight: false,
  # In insert mode, show the current symbol signature automatically
  showSignature: true,
  # In insert mode, echo the current symbol signature in the status line
  # instead of showing it in a popup
  echoSignature: false,
  # Automatically highlight diagnostics messages from LSP server
  autoHighlightDiags: true,
  # Automatically populate the location list with new diagnostics
  autoPopulateDiags: false,
  # Show the symbol documentation in the preview window instead of in a popup
  hoverInPreview: false,
  # Focus on the location list window after LspShowReferences
  keepFocusInReferences: false,
  # Suppress adding a new line on completion selection with <CR>
  noNewlineInCompletion: false,
  # Outline window size
  outlineWinSize: 20,
  # Open outline window on right side
  outlineOnRight: false,
  # Suppress diagnostic hover from appearing when the mouse is over the line
  # instead of the signature
  noDiagHoverOnLine: true,
  # Show a diagnostic message on a status line
  showDiagOnStatusLine: false,
  # Make diagnostics show in a popup instead of echoing
  showDiagInPopup: true,
  # Default diagnostic highlight on lines
  diagLineHL: 'DiffAdd',
  # Show a diagnostic messages with virtual text
  showDiagWithVirtualText: false,
  # The highlight group used for a diagnostics virtual text
  diagVirtualTextHL: 'LineNr',
  # Highlight diagnostics inline
  highlightDiagInline: false,
  # The highlight group used inline Error diagnostics
  diagInlineErrorHL: 'SpellBad',
  # The highlight group used inline Warning diagnostics
  diagInlineWarningHL: 'SpellCap',
  # The highlight group used inline Info diagnostics
  diagInlineInfoHL: 'SpellRare',
  # The highlight group used inline Hint diagnostics
  diagInlineHintHL: 'SpellLocal',
  # Don't print message when a configured language server is missing.
  ignoreMissingServer: false,
  # Use a floating menu to show the code action menu instead of asking for input
  usePopupInCodeAction: false,
  # enable snippet completion support
  snippetSupport: false,
  # enable inlay hints
  showInlayHints: false,
  # hide disabled code actions
  hideDisabledCodeActions: false,
  # icase | fuzzy | case match for language servers that replies with a full
  # list of completion items
  completionMatcher: 'case',
  # diagnostics signs options
  diagSignErrorText: 'E>',
  diagSignErrorTexthl: 'ErrorMsg',
  diagSignWarningText: 'W>',
  diagSignWarningTexthl: 'Search',
  diagSignInfoText: 'I>',
  diagSignInfoTexthl: 'Pmenu',
  diagSignHintText: 'H>',
  diagSignHintTexthl: 'Question',
}

# set the LSP plugin options from the user provided option values
export def OptionsSet(opts: dict<any>)
  lspOptions->extend(opts)
  if !has('patch-9.0.0178')
    lspOptions.showInlayHints = false
  endif
  if !has('patch-9.0.1157')
    lspOptions.showDiagWithVirtualText = false
  endif
enddef

# return a copy of the LSP plugin options
export def OptionsGet(): dict<any>
  return lspOptions->deepcopy()
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
