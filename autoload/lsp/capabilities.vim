vim9script

# Functions for managing the LSP server and client capabilities

import './options.vim' as opt

# Process the server capabilities
export def ProcessServerCaps(lspserver: dict<any>, caps: dict<any>)
  # completionProvider
  if lspserver.caps->has_key('completionProvider')
    lspserver.isCompletionProvider = true
    if lspserver.caps.completionProvider->has_key('resolveProvider')
      lspserver.isCompletionResolveProvider =
			lspserver.caps.completionProvider.resolveProvider
    else
      lspserver.isCompletionResolveProvider = false
    endif
  else
    lspserver.isCompletionProvider = false
    lspserver.isCompletionResolveProvider = false
  endif

  # definitionProvider
  if lspserver.caps->has_key('definitionProvider')
    if lspserver.caps.definitionProvider->type() == v:t_bool
      lspserver.isDefinitionProvider = lspserver.caps.definitionProvider
    else
      lspserver.isDefinitionProvider = true
    endif
  else
    lspserver.isDefinitionProvider = false
  endif

  # declarationProvider
  if lspserver.caps->has_key('declarationProvider')
    if lspserver.caps.declarationProvider->type() == v:t_bool
      lspserver.isDeclarationProvider = lspserver.caps.declarationProvider
    else
      lspserver.isDeclarationProvider = true
    endif
  else
    lspserver.isDeclarationProvider = false
  endif

  # typeDefinitionProvider
  if lspserver.caps->has_key('typeDefinitionProvider')
    if lspserver.caps.typeDefinitionProvider->type() == v:t_bool
      lspserver.isTypeDefinitionProvider = lspserver.caps.typeDefinitionProvider
    else
      lspserver.isTypeDefinitionProvider = true
    endif
  else
    lspserver.isTypeDefinitionProvider = false
  endif

  # implementationProvider
  if lspserver.caps->has_key('implementationProvider')
    if lspserver.caps.implementationProvider->type() == v:t_bool
      lspserver.isImplementationProvider = lspserver.caps.implementationProvider
    else
      lspserver.isImplementationProvider = true
    endif
  else
    lspserver.isImplementationProvider = false
  endif

  # signatureHelpProvider
  if lspserver.caps->has_key('signatureHelpProvider')
    lspserver.isSignatureHelpProvider = true
  else
    lspserver.isSignatureHelpProvider = false
  endif

  # hoverProvider
  if lspserver.caps->has_key('hoverProvider')
    if lspserver.caps.hoverProvider->type() == v:t_bool
      lspserver.isHoverProvider = lspserver.caps.hoverProvider
    else
      lspserver.isHoverProvider = true
    endif
  else
    lspserver.isHoverProvider = false
  endif

  # referencesProvider
  if lspserver.caps->has_key('referencesProvider')
    if lspserver.caps.referencesProvider->type() == v:t_bool
      lspserver.isReferencesProvider = lspserver.caps.referencesProvider
    else
      lspserver.isReferencesProvider = true
    endif
  else
    lspserver.isReferencesProvider = false
  endif

  # documentHighlightProvider
  if lspserver.caps->has_key('documentHighlightProvider')
    if lspserver.caps.documentHighlightProvider->type() == v:t_bool
      lspserver.isDocumentHighlightProvider =
				lspserver.caps.documentHighlightProvider
    else
      lspserver.isDocumentHighlightProvider = true
    endif
  else
    lspserver.isDocumentHighlightProvider = false
  endif

  # documentSymbolProvider
  if lspserver.caps->has_key('documentSymbolProvider')
    if lspserver.caps.documentSymbolProvider->type() == v:t_bool
      lspserver.isDocumentSymbolProvider =
				lspserver.caps.documentSymbolProvider
    else
      lspserver.isDocumentSymbolProvider = true
    endif
  else
    lspserver.isDocumentSymbolProvider = false
  endif

  # documentFormattingProvider
  if lspserver.caps->has_key('documentFormattingProvider')
    if lspserver.caps.documentFormattingProvider->type() == v:t_bool
      lspserver.isDocumentFormattingProvider =
				lspserver.caps.documentFormattingProvider
    else
      lspserver.isDocumentFormattingProvider = true
    endif
  else
    lspserver.isDocumentFormattingProvider = false
  endif

  # callHierarchyProvider
  if lspserver.caps->has_key('callHierarchyProvider')
    if lspserver.caps.callHierarchyProvider->type() == v:t_bool
      lspserver.isCallHierarchyProvider =
				lspserver.caps.callHierarchyProvider
    else
      lspserver.isCallHierarchyProvider = true
    endif
  else
    lspserver.isCallHierarchyProvider = false
  endif

  # typeHierarchyProvider
  if lspserver.caps->has_key('typeHierarchyProvider')
    lspserver.isTypeHierarchyProvider = true
  else
    lspserver.isTypeHierarchyProvider = false
  endif

  # renameProvider
  if lspserver.caps->has_key('renameProvider')
    if lspserver.caps.renameProvider->type() == v:t_bool
      lspserver.isRenameProvider = lspserver.caps.renameProvider
    else
      lspserver.isRenameProvider = true
    endif
  else
    lspserver.isRenameProvider = false
  endif

  # codeActionProvider
  if lspserver.caps->has_key('codeActionProvider')
    if lspserver.caps.codeActionProvider->type() == v:t_bool
      lspserver.isCodeActionProvider = lspserver.caps.codeActionProvider
    else
      lspserver.isCodeActionProvider = true
    endif
  else
    lspserver.isCodeActionProvider = false
  endif

  # codeLensProvider
  if lspserver.caps->has_key('codeLensProvider')
    lspserver.isCodeLensProvider = true
    if lspserver.caps.codeLensProvider->has_key('resolveProvider')
      lspserver.isCodeLensResolveProvider = true
    else
      lspserver.isCodeLensResolveProvider = false
    endif
  else
    lspserver.isCodeLensProvider = false
  endif

  # workspaceSymbolProvider
  if lspserver.caps->has_key('workspaceSymbolProvider')
    if lspserver.caps.workspaceSymbolProvider->type() == v:t_bool
      lspserver.isWorkspaceSymbolProvider =
				lspserver.caps.workspaceSymbolProvider
    else
      lspserver.isWorkspaceSymbolProvider = true
    endif
  else
    lspserver.isWorkspaceSymbolProvider = false
  endif

  # selectionRangeProvider
  if lspserver.caps->has_key('selectionRangeProvider')
    if lspserver.caps.selectionRangeProvider->type() == v:t_bool
      lspserver.isSelectionRangeProvider =
				lspserver.caps.selectionRangeProvider
    else
      lspserver.isSelectionRangeProvider = true
    endif
  else
    lspserver.isSelectionRangeProvider = false
  endif

  # foldingRangeProvider
  if lspserver.caps->has_key('foldingRangeProvider')
    if lspserver.caps.foldingRangeProvider->type() == v:t_bool
      lspserver.isFoldingRangeProvider = lspserver.caps.foldingRangeProvider
    else
      lspserver.isFoldingRangeProvider = true
    endif
  else
    lspserver.isFoldingRangeProvider = false
  endif

  # inlayHintProvider
  if lspserver.caps->has_key('inlayHintProvider')
    if lspserver.caps.inlayHintProvider->type() == v:t_bool
      lspserver.isInlayHintProvider = lspserver.caps.inlayHintProvider
    else
      lspserver.isInlayHintProvider = true
    endif
  else
    lspserver.isInlayHintProvider = false
  endif

  # clangdInlayHintsProvider
  if lspserver.caps->has_key('clangdInlayHintsProvider')
    lspserver.isClangdInlayHintsProvider =
					lspserver.caps.clangdInlayHintsProvider
  else
    lspserver.isClangdInlayHintsProvider = false
  endif

  # textDocument/didSave notification
  if lspserver.caps->has_key('textDocumentSync')
    if lspserver.caps.textDocumentSync->type() == v:t_bool
		|| lspserver.caps.textDocumentSync->type() == v:t_number
      lspserver.supportsDidSave = lspserver.caps.textDocumentSync
    else
      if lspserver.caps.textDocumentSync->type() == v:t_dict
	if lspserver.caps.textDocumentSync->has_key('save')
	  if lspserver.caps.textDocumentSync.save->type() == v:t_bool
	    || lspserver.caps.textDocumentSync.save->type() == v:t_number
	    lspserver.supportsDidSave = lspserver.caps.textDocumentSync.save
	  elseif lspserver.caps.textDocumentSync.save->type() == v:t_dict
	    lspserver.supportsDidSave = true
	  else
	    lspserver.supportsDidSave = false
	  endif
	else
	  lspserver.supportsDidSave = false
	endif
      else
	lspserver.supportsDidSave = false
      endif
    endif
  else
    lspserver.supportsDidSave = false
  endif
enddef

# Return all the LSP client capabilities
export def GetClientCaps(): dict<any>
  # client capabilities (ClientCapabilities)
  var clientCaps: dict<any> = {
    workspace: {
      workspaceFolders: true,
      applyEdit: true,
      configuration: true
    },
    textDocument: {
      callHierarchy: {
	dynamicRegistration: false
      },
      codeAction: {
	dynamicRegistration: false,
	codeActionLiteralSupport: {
	  codeActionKind: {
	    valueSet: ['', 'quickfix', 'refactor', 'refactor.extract',
			'refactor.inline', 'refactor.rewrite', 'source',
			'source.organizeImports']
	  }
	},
        isPreferredSupport: true,
	disabledSupport: true
      },
      codeLens: {
	dynamicRegistration: false
      },
      completion: {
	dynamicRegistration: false,
	completionItem: {
	  documentationFormat: ['plaintext', 'markdown'],
	  resolveSupport: {properties: ['detail', 'documentation']},
	  snippetSupport: opt.lspOptions.snippetSupport
	},
	completionItemKind: {valueSet: range(1, 25)}
      },
      documentSymbol: {
	dynamicRegistration: false,
	hierarchicalDocumentSymbolSupport: true,
	symbolKind: {valueSet: range(1, 25)}
      },
      hover: {
        contentFormat: ['plaintext', 'markdown']
      },
      foldingRange: {lineFoldingOnly: true},
      inlayHint: {dynamicRegistration: false},
      synchronization: {
	didSave: true
      },
      declaration: {linkSupport: true},
      definition: {linkSupport: true},
      typeDefinition: {linkSupport: true},
      implementation: {linkSupport: true},
      signatureHelp: {
	signatureInformation: {
	  documentationFormat: ['plaintext', 'markdown'],
	  activeParameterSupport: true
	}
      }
    },
    window: {},
    general: {
      # Currently we always send character count as position offset,
      # which meanas only utf-32 is supported.
      # Adding utf-16 simply for good mesure, as I'm scared some servers will
      # give up if they don't support utf-32 only.
      positionEncodings: ['utf-32', 'utf-16']
    },
    # This is the way clangd expects to be informated about supported encodings:
    # https://clangd.llvm.org/extensions#utf-8-offsets
    offsetEncoding: ['utf-32', 'utf-16']
  }

  return clientCaps
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
