vim9script

# LSP plugin options
# User can override these by calling the OptionsSet() function.
export var lspOptions: dict<any> = {
  # In insert mode, complete the current symbol automatically
  # Otherwise, use omni-completion
  autoComplete: true,
  # In normal mode, highlight the current symbol automatically
  autoHighlight: false,
  # Automatically highlight diagnostics messages from LSP server
  autoHighlightDiags: true,
  # Automatically populate the location list with new diagnostics
  autoPopulateDiags: false,
  # icase | fuzzy | case match for language servers that replies with a full
  # list of completion items
  completionMatcher: 'case',
  # diagnostics signs options
  diagSignErrorText: 'E>',
  diagSignHintText: 'H>',
  diagSignInfoText: 'I>',
  diagSignWarningText: 'W>',
  # In insert mode, echo the current symbol signature in the status line
  # instead of showing it in a popup
  echoSignature: false,
  # hide disabled code actions
  hideDisabledCodeActions: false,
  # Highlight diagnostics inline
  highlightDiagInline: false,
  # Show the symbol documentation in the preview window instead of in a popup
  hoverInPreview: false,
  # Don't print message when a configured language server is missing.
  ignoreMissingServer: false,
  # Focus on the location list window after LspShowReferences
  keepFocusInReferences: false,
  # If not apply LSP server-initiated actions after completion
  # specially if some others plugins had registered to do that
  noAdditionalTextEdits: false,
  # instead of the signature
  noDiagHoverOnLine: true,
  # Suppress adding a new line on completion selection with <CR>
  noNewlineInCompletion: false,
  # Open outline window on right side
  outlineOnRight: false,
  # Outline window size
  outlineWinSize: 20,
  # Make diagnostics show in a popup instead of echoing
  showDiagInPopup: true,
  # Suppress diagnostic hover from appearing when the mouse is over the line
  # Show a diagnostic message on a status line
  showDiagOnStatusLine: false,
  # Show a diagnostic messages with virtual text
  showDiagWithVirtualText: false,
  # enable inlay hints
  showInlayHints: false,
  # In insert mode, show the current symbol signature automatically
  showSignature: true,
  # enable snippet completion support
  snippetSupport: false,
  # enable SirVer/ultisnips completion support
  ultisnipsSupport: false,
  # Use a floating menu to show the code action menu instead of asking for input
  usePopupInCodeAction: false,
  # ShowReferences in a quickfix list instead of a location list`
  useQuickfixForLocations: false,
  # Enable support for custom completion kinds
  customCompletionKinds: false,
  # A dictionary with all completion kinds that you want to customize
  completionKinds: {}
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
