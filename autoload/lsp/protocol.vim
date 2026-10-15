vim9script

# Named constants for the numeric enums defined by the Language Server
# Protocol specification, so callers don't have to compare against bare
# integer literals.
# Refer to https://microsoft.github.io/language-server-protocol/specification
# for the Language Server Protocol (LSP) specification.

# TextDocumentSyncKind
export const TextDocumentSyncKindNone = 0
export const TextDocumentSyncKindFull = 1
export const TextDocumentSyncKindIncremental = 2

# DocumentHighlightKind
export const DocumentHighlightKindText = 1
export const DocumentHighlightKindRead = 2
export const DocumentHighlightKindWrite = 3

# CompletionTriggerKind
export const CompletionTriggerKindInvoked = 1
export const CompletionTriggerKindTriggerCharacter = 2
export const CompletionTriggerKindTriggerForIncompleteCompletions = 3

# InsertTextFormat
export const InsertTextFormatPlainText = 1
export const InsertTextFormatSnippet = 2

# InsertTextMode
export const InsertTextModeAsIs = 1
export const InsertTextModeAdjustIndentation = 2

# MessageType
export const MessageTypeError = 1
export const MessageTypeWarning = 2
export const MessageTypeInfo = 3
export const MessageTypeLog = 4

# InlayHintKind
export const InlayHintKindType = 1
export const InlayHintKindParameter = 2

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
