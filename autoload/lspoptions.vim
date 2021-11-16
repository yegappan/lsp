vim9script

# LSP plugin options
# User can override these by calling the lsp#setOptions() function.
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
  autoHighlightDiags: true
}
