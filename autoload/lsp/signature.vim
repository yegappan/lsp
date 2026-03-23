vim9script

# Functions related to handling LSP symbol signature help.

import './options.vim' as opt
import './buffer.vim' as buf

# Keep the current signature help session in one place so overload
# navigation can update the existing UI without asking the server again.
var sig_state = {
  signatures: [],       # SignatureInformation[] from the latest server reply
  index: 0,             # index into signatures[] for the currently displayed overload
  activeParam: 0,       # top-level SignatureHelp.activeParameter value (-1 = suppress)
  lspserver: {},        # server that owns the current session
  bnr: -1,              # buffer the session is anchored to
}

# Mirrors LSP 3.17 SignatureHelpTriggerKind enum values.
const SIG_TRIGGER_KIND_INVOKED = 1
const SIG_TRIGGER_KIND_TRIGGER_CHAR = 2
const SIG_TRIGGER_KIND_CONTENT_CHANGE = 3
const SIG_TRIGGER_DELAY_DEFAULT = 50          # ms: debounce for invoked/trigger-char events
const SIG_TRIGGER_DELAY_CONTENT_CHANGE = 120  # ms: debounce for noisy cursor/text events
const SIG_POPUP_CLOSE_INTERNAL = -7777        # internal close reason to skip close-callback cleanup

# -----------------------------------------------------------------------------
# State And Timers
# -----------------------------------------------------------------------------

# Show the signature using "textDocument/signatureHelp" LSP method.
# Invoked from an insert-mode mapping, so return an empty string.
def g:LspShowSignature(triggerKind: number = SIG_TRIGGER_KIND_INVOKED,
			      triggerChar: string = ''): string
  var lspserver: dict<any> = buf.CurbufGetServerChecked('signatureHelp')
  if lspserver->empty()
    return ''
  endif

  # First send all the changes in the current buffer to the LSP server.
  listener_flush()
  lspserver.showSignature(triggerKind, triggerChar)

  return ''
enddef

# Use a script-local timer instance that can be reused.
var signature_timer = -1
var signature_timer_bufnr = -1
var signature_timer_trigger_kind = SIG_TRIGGER_KIND_INVOKED
var signature_timer_trigger_char = ''
var signature_contentchange_state: dict<number> = {
  bnr: -1,
  changedtick: -1,
  lnum: -1,
  col: -1
}

# Clear pending timer metadata after execution or cancellation.
def ResetSignatureTimerState()
  signature_timer = -1
  signature_timer_bufnr = -1
  signature_timer_trigger_kind = SIG_TRIGGER_KIND_INVOKED
  signature_timer_trigger_char = ''
enddef

# Reset dedupe state for content-change based retriggers.
def ResetSignatureContentChangeState()
  signature_contentchange_state = {
    bnr: -1,
    changedtick: -1,
    lnum: -1,
    col: -1
  }
enddef

# Capture a lightweight content-change fingerprint for dedupe.
def GetContentChangeSnapshot(): dict<number>
  var bnr = bufnr()
  return {
    bnr: bnr,
    changedtick: bnr->getbufvar('changedtick', -1),
    lnum: line('.'),
    col: charcol('.')
  }
enddef

# Check whether the latest event matches the previous processed snapshot.
def IsDuplicateContentChange(snapshot: dict<number>): bool
  return signature_contentchange_state.changedtick == snapshot.changedtick
    && signature_contentchange_state.lnum == snapshot.lnum
    && signature_contentchange_state.col == snapshot.col
    && signature_contentchange_state.bnr == snapshot.bnr
enddef

# Persist the last processed content-change snapshot.
def SaveContentChangeSnapshot(snapshot: dict<number>)
  signature_contentchange_state = snapshot
enddef

# Use a slightly longer delay for noisy content-change retriggers.
def GetSignatureTriggerDelay(triggerKind: number): number
  if triggerKind == SIG_TRIGGER_KIND_CONTENT_CHANGE
    return SIG_TRIGGER_DELAY_CONTENT_CHANGE
  endif

  return SIG_TRIGGER_DELAY_DEFAULT
enddef

# Timer callback that replays the deferred signature request safely.
def LspShowSignatureCb(timer: number)
  if timer != signature_timer
    return
  endif

  var timer_bnr = signature_timer_bufnr
  var triggerKind = signature_timer_trigger_kind
  var triggerChar = signature_timer_trigger_char
  ResetSignatureTimerState()

  # Show signature only in insert mode and only for the buffer that scheduled
  # the timer.
  if mode() ==# 'i' && bufnr() == timer_bnr
    call g:LspShowSignature(triggerKind, triggerChar)
  endif
enddef

# Debounce signature requests so rapid insert-mode events are coalesced.
def LspShowSignatureDelayed(triggerKind: number, triggerChar: string)
  # Cancel old timer if still running.
  if signature_timer != -1
    call timer_stop(signature_timer)
  endif

  # Delay signature requests so rapid insert-mode events are coalesced.
  signature_timer_bufnr = bufnr()
  signature_timer_trigger_kind = triggerKind
  signature_timer_trigger_char = triggerChar
  signature_timer = timer_start(GetSignatureTriggerDelay(triggerKind), function('LspShowSignatureCb'))
enddef

# -----------------------------------------------------------------------------
# Session Lifecycle
# -----------------------------------------------------------------------------

# A signature session is active only when state, server, and buffer all match.
def SignatureSessionActive(lspserver: dict<any>): bool
  return !sig_state.signatures->empty()
	&& !sig_state.lspserver->empty()
	&& sig_state.lspserver.id == lspserver.id
	&& sig_state.bnr == bufnr()
enddef

# Return the number of parameters declared by a signature.
def GetSignatureParameterCount(sig: dict<any>): number
  var params = sig->get('parameters', [])

  return params->len()
enddef

# Normalize an optional LSP activeParameter value.
# Returns:
#   -1 for null/suppress
#   >= 0 for a valid numeric value
#    0 for missing or unsupported values
def NormalizeOptionalActiveParameter(value: any): number
  # Recognize null in a version-agnostic way so
  # SignatureInformation.activeParameter: null suppresses highlighting.
  if string(value) ==# 'null' || string(value) ==# 'v:none'
    return -1
  endif

  if value->type() == v:t_number && value >= 0
    return value
  endif

  return 0
enddef

# Apply the SignatureHelp.activeParameter fallback rules to the current
# signature. The stored top-level value may clamp to the last parameter for
# variadic tails, or propagate the suppress sentinel.
def GetTopLevelActiveParameter(sig: dict<any>, paramCount: number): number
  var activeParam = sig_state.activeParam
  if activeParam < 0
    return -1
  endif

  if paramCount == 0
    return 0
  endif

  if activeParam >= paramCount
    return paramCount - 1
  endif

  return activeParam
enddef

# Resolve the effective active parameter with the two-level fallback chain
# defined by LSP 3.17:
#  1. SignatureInformation.activeParameter — null → suppress; in-range → use;
#     out-of-range → fall through to level 2.
#  2. SignatureHelp.activeParameter (stored in sig_state.activeParam) —
#     null/negative → suppress; out-of-range → last param (variadic tail).
def GetCurrentActiveParameter(): number
  var sig: dict<any> = GetCurrentSignature()
  if sig->empty()
    return 0
  endif

  var paramCount = GetSignatureParameterCount(sig)

  # Level 1: per-signature override.
  if sig->has_key('activeParameter')
    var sigActiveRaw = sig.activeParameter
    # Distinguish explicit 0 from unsupported values: only numeric values
    # are valid here. null-like values explicitly suppress highlighting.
    if string(sigActiveRaw) ==# 'null' || string(sigActiveRaw) ==# 'v:none'
      return -1
    endif
    if sigActiveRaw->type() != v:t_number || sigActiveRaw < 0
      return GetTopLevelActiveParameter(sig, paramCount)
    endif

    var sigActive = sigActiveRaw
    if sigActive < 0
      return -1
    endif
    if sigActive >= 0
      if paramCount == 0
        return 0
      endif
      if sigActive < paramCount
        return sigActive
      endif
      # Out of range: spec says fall back to the top-level value (level 2).
    endif
  endif

  return GetTopLevelActiveParameter(sig, paramCount)
enddef

# Build the activeSignatureHelp payload used for retrigger context.
def GetCurrentSignatureHelpState(): dict<any>
  if sig_state.signatures->empty()
    return {}
  endif

  # LSP spec: activeParameter is uinteger | null. Map the internal -1 suppress
  # sentinel back to null so the wire value is spec-compliant.
  var activeParam = GetCurrentActiveParameter()
  var wireParam: any = activeParam < 0 ? null : activeParam

  return {
    signatures: sig_state.signatures,
    activeSignature: sig_state.index,
    activeParameter: wireParam
  }
enddef

# Return true when an async signature-help reply still matches the editor
# state that triggered the request.
def SignatureRequestContextMatches(reqctx: dict<number>): bool
  return reqctx.bnr == bufnr()
         && reqctx.changedtick == reqctx.bnr->getbufvar('changedtick', -1)
         && reqctx.lnum == line('.')
         && reqctx.col == charcol('.')
enddef

# Snapshot the current editor state so stale async signature replies can be
# discarded when the user moves or edits before the server responds.
export def SignatureRequestContextGet(): dict<number>
  var bnr = bufnr()
  return {
    bnr: bnr,
    changedtick: bnr->getbufvar('changedtick', -1),
    lnum: line('.'),
    col: charcol('.')
  }
enddef

# Popup close callback: if the signature popup is closed out-of-band (for
# example by the user), immediately clear signature session state and restore
# temporary overload-navigation mappings.
def SignaturePopupCloseCb(lspserver: dict<any>, popupid: number, result: number)
  if result == SIG_POPUP_CLOSE_INTERNAL
    return
  endif

  if lspserver.signaturePopup == popupid
    lspserver.signaturePopup = -1
    ResetSignatureState()
  endif
enddef

# Close the signature popup window.
def CloseSignaturePopup(lspserver: dict<any>)
  if lspserver.signaturePopup != -1
    popup_close(lspserver.signaturePopup, SIG_POPUP_CLOSE_INTERNAL)
  endif
  lspserver.signaturePopup = -1
  ResetSignatureState()
enddef

# Close signature UI for the current buffer, if a server is attached.
def CloseCurBufSignaturePopup()
  var lspserver: dict<any> = buf.CurbufGetServer('signatureHelp')
  if lspserver->empty()
    return
  endif

  CloseSignaturePopup(lspserver)
enddef

# Clear the active signature session when the popup goes away or a new session
# starts. This also tears down any temporary navigation mappings.
def ResetSignatureState()
  DisableSignatureSessionAutocmds()
  sig_state.signatures = []
  sig_state.index = 0
  sig_state.activeParam = 0
  sig_state.lspserver = {}
  sig_state.bnr = -1
  ResetSignatureContentChangeState()
enddef

# -----------------------------------------------------------------------------
# Trigger Pipeline
# -----------------------------------------------------------------------------

# Add unseen trigger characters to both the merged auto-trigger list and the
# lookup table used by the insert-mode hot path.
def AddSignatureChars(chars: list<string>, lookup: dict<bool>, merged: list<string>)
  for ch in chars
    if lookup->has_key(ch)
      continue
    endif
    lookup[ch] = true
    merged->add(ch)
  endfor
enddef

# Build and cache signature trigger metadata on the server so trigger checks in
# insert mode do constant-time dictionary lookups instead of repeated list
# scans.
def GetSignatureTriggerConfig(lspserver: dict<any>): dict<any>
  if lspserver->has_key('signatureTriggerConfig')
    return lspserver.signatureTriggerConfig
  endif

  var provider = lspserver.caps.signatureHelpProvider
  var triggerChars = provider->get('triggerCharacters', [])
  var retriggerChars = provider->get('retriggerCharacters', [])
  var triggerLookup: dict<bool> = {}
  var retriggerLookup: dict<bool> = {}
  var autoChars: list<string> = []

  AddSignatureChars(triggerChars, triggerLookup, autoChars)
  AddSignatureChars(retriggerChars, retriggerLookup, autoChars)

  lspserver.signatureTriggerConfig = {
    triggerLookup: triggerLookup,
    retriggerLookup: retriggerLookup,
    autoChars: autoChars
  }

  return lspserver.signatureTriggerConfig
enddef

# Build SignatureHelpContext according to trigger source and session state.
export def GetSignatureHelpContext(lspserver: dict<any>, triggerKind: number,
					   triggerChar: string): dict<any>
  CleanupStaleSignatureSession(lspserver)
  var isRetrigger = ShouldTreatAsRetrigger(lspserver)
  var context = {
    triggerKind: triggerKind,
    isRetrigger: isRetrigger
  }

  if triggerKind == SIG_TRIGGER_KIND_TRIGGER_CHAR && !triggerChar->empty()
    context.triggerCharacter = triggerChar
  endif

  if isRetrigger
    context.activeSignatureHelp = GetCurrentSignatureHelpState()
  endif

  return context
enddef

# Mapping fallback path for typed trigger characters on older Vim versions.
def g:LspShowSignatureTriggerChar(ch: string): string
  var lspserver: dict<any> = buf.CurbufGetServer('signatureHelp')
  if lspserver->empty()
    return ''
  endif

  # Clean up stale state so retrigger semantics only apply when signature UI
  # is actually active.
  CleanupStaleSignatureSession(lspserver)

  if GetSignatureTriggerKind(lspserver, ch) < 0
    return ''
  endif

  return g:LspShowSignature(SIG_TRIGGER_KIND_TRIGGER_CHAR, ch)
enddef

# Autocmd path for typed trigger characters using KeyInputPre.
def g:LspHandleSignatureTriggerChar(ch: string): void
  var lspserver: dict<any> = buf.CurbufGetServer('signatureHelp')
  if lspserver->empty()
    return
  endif

  # Keep trigger-based retriggers consistent with actual signature UI
  # visibility.
  CleanupStaleSignatureSession(lspserver)

  var triggerKind = GetSignatureTriggerKind(lspserver, ch)
  if triggerKind < 0
    return
  endif

  LspShowSignatureDelayed(triggerKind, ch)
enddef

# Retrigger on cursor/text changes while signature session is active.
def g:LspHandleSignatureContentChange(): void
  var lspserver: dict<any> = buf.CurbufGetServer('signatureHelp')
  if lspserver->empty() || !SignatureSessionActive(lspserver)
    return
  endif

  # Content-change retriggers are valid only while the signature popup is
  # still visible. If the popup was closed out-of-band, clear stale session
  # state and stop retriggering.
  CleanupStaleSignatureSession(lspserver)
  if !ShouldTreatAsRetrigger(lspserver)
    return
  endif

  var snapshot = GetContentChangeSnapshot()
  if IsDuplicateContentChange(snapshot)
    return
  endif

  SaveContentChangeSnapshot(snapshot)

  LspShowSignatureDelayed(SIG_TRIGGER_KIND_CONTENT_CHANGE, '')
enddef

# Merge trigger and retrigger characters into one deduplicated list.
def GetAutoSignatureTriggerCharacters(lspserver: dict<any>): list<string>
  return GetSignatureTriggerConfig(lspserver).autoChars
enddef

# True when character is configured as an initial signature trigger.
def IsSignatureTriggerCharacter(lspserver: dict<any>, ch: string): bool
  return GetSignatureTriggerConfig(lspserver).triggerLookup->has_key(ch)
enddef

# True when character should trigger or retrigger signature help.
def IsSignatureRetriggerCharacter(lspserver: dict<any>, ch: string): bool
  var triggerConfig = GetSignatureTriggerConfig(lspserver)

  return triggerConfig.triggerLookup->has_key(ch)
	 || triggerConfig.retriggerLookup->has_key(ch)
enddef

# Permit retrigger characters only while an active signature UI is present.
def ShouldTriggerSignature(lspserver: dict<any>, ch: string): bool
  if IsSignatureTriggerCharacter(lspserver, ch)
    return true
  endif

  return ShouldTreatAsRetrigger(lspserver) && IsSignatureRetriggerCharacter(lspserver, ch)
enddef

# Map a typed character to trigger kind or return -1 when ignored.
def GetSignatureTriggerKind(lspserver: dict<any>, ch: string): number
  if ShouldTriggerSignature(lspserver, ch)
    return SIG_TRIGGER_KIND_TRIGGER_CHAR
  endif

  return -1
enddef

# True when the signature popup window is currently open and rendered on screen.
def SignaturePopupVisible(lspserver: dict<any>): bool
  if !SignatureSessionActive(lspserver)
    return false
  endif

  return lspserver.signaturePopup != -1
	 && popup_list()->index(lspserver.signaturePopup) != -1
enddef

# Determine whether signature UI is currently visible to the user.
def SignatureUiActive(lspserver: dict<any>): bool
  if opt.lspOptions.echoSignature
    # In echo mode there is no popup id to track visibility. Treat an active
    # signature session as visible UI state.
    return SignatureSessionActive(lspserver)
  endif

  return SignaturePopupVisible(lspserver)
enddef

# Drop stale signature sessions when their UI is no longer visible.
def CleanupStaleSignatureSession(lspserver: dict<any>)
  if SignatureSessionActive(lspserver) && !SignatureUiActive(lspserver)
    ResetSignatureState()
  endif
enddef

# Retrigger paths are valid only while both session and UI are active.
def ShouldTreatAsRetrigger(lspserver: dict<any>): bool
  return SignatureSessionActive(lspserver) && SignatureUiActive(lspserver)
enddef

# -----------------------------------------------------------------------------
# Rendering Pipeline
# -----------------------------------------------------------------------------

# Convert signature or parameter documentation to display lines and an
# optional popup filetype.
def GetSignatureDocumentation(lspserver: dict<any>, documentation: any): dict<any>
  var doc = {lines: [], filetype: ''}

  var doc_type = documentation->type()
  if doc_type == v:t_string
    if !documentation->empty()
      doc.lines = documentation->split("\n")
    endif
    return doc
  endif

  if doc_type != v:t_dict || !documentation->has_key('value')
    return doc
  endif

  var doc_kind: string = documentation->get('kind', 'plaintext')
  if doc_kind ==# 'markdown'
    doc.filetype = 'lspgfm'
  elseif doc_kind !=# 'plaintext'
    lspserver.errorLog(
	$'{strftime("%m/%d/%y %T")}: Unsupported signature documentation kind ({doc_kind})'
      )
    return doc
  endif

  if documentation.value->type() == v:t_string && !documentation.value->empty()
    doc.lines = documentation.value->split("\n")
  endif

  return doc
enddef

# Return docs attached to the currently active parameter, if present.
def GetActiveParameterDocumentation(lspserver: dict<any>, sig: dict<any>,
				    activeParam: number): dict<any>
  var doc = {lines: [], filetype: ''}

  # -1 is the suppress sentinel: no active parameter, so no parameter doc.
  if activeParam < 0 || !sig->has_key('parameters') || activeParam >= sig.parameters->len()
    return doc
  endif

  var paramInfo: dict<any> = sig.parameters[activeParam]
  if !paramInfo->has_key('documentation')
    return doc
  endif

  return GetSignatureDocumentation(lspserver, paramInfo.documentation)
enddef

# Build a short single-line summary for command-line echo mode.
def GetEchoDocumentationSummary(doc: dict<any>): string
  const RE_CODE_BLOCK = '^```'
  const RE_HEADER = '^#\+\s*'

  for line in doc.lines
    var text = line->trim()
    if text->empty() || text =~ RE_CODE_BLOCK
      continue
    endif

    text = text->substitute(RE_HEADER, '', '')
    text = text->substitute('\s\+', ' ', 'g')
    if !text->empty()
      return text
    endif
  endfor

  return ''
enddef

# Append a titled documentation section to popup lines when non-empty.
def AddSignatureDocSection(lines: list<string>, heading: string, doc: dict<any>)
  if doc.lines->empty()
    return
  endif

  if !lines->empty()
    lines->add('')
  endif
  lines->add(heading)
  lines->extend(doc.lines)
enddef

# Pick markdown highlighting for the popup when any attached documentation is
# markdown.
def GetSignatureDocFiletype(paramDoc: dict<any>, sigDoc: dict<any>): string
  if paramDoc.filetype ==# 'lspgfm' || sigDoc.filetype ==# 'lspgfm'
    return 'lspgfm'
  endif

  return ''
enddef

# Prefer parameter docs for the single-line echo summary, then fall back to the
# signature-level documentation.
def GetSignatureDocSummary(paramDoc: dict<any>, sigDoc: dict<any>): string
  var docSummary = GetEchoDocumentationSummary(paramDoc)
  if docSummary->empty()
    docSummary = GetEchoDocumentationSummary(sigDoc)
  endif

  return docSummary
enddef

# Build unified display payload for popup and echo rendering paths.
def GetSignatureDisplayInfo(lspserver: dict<any>, sig: dict<any>,
			    sigidx: number, total: number,
			    activeParam: number): dict<any>
  var text: string = FormatSignatureText(sig, sigidx, total)
  var sigDoc = {lines: [], filetype: ''}
  var lines = [text]
  var docSummary = ''
  var filetype = ''

  if opt.lspOptions.showSignatureDocs
    var paramDoc = GetActiveParameterDocumentation(lspserver, sig, activeParam)
    if sig->has_key('documentation')
      sigDoc = GetSignatureDocumentation(lspserver, sig.documentation)
    endif

    AddSignatureDocSection(lines, 'Parameter:', paramDoc)
    AddSignatureDocSection(lines, 'Signature:', sigDoc)
    filetype = GetSignatureDocFiletype(paramDoc, sigDoc)
    docSummary = GetSignatureDocSummary(paramDoc, sigDoc)
  endif

  return {
    text: text,
    lines: lines,
    filetype: filetype,
    docSummary: docSummary
  }
enddef

# Append a compact overload indicator so the user can see where they are while
# cycling through multiple signatures.
def FormatSignatureText(sig: dict<any>, sigidx: number, total: number): string
  var text: string = sig.label
  if total > 1
    text = text->trim('', 2)
    text ..= $"  ({sigidx + 1}/{total})"
  endif

  return text
enddef

# Convert the active parameter description from the LSP response into the text
# range that should be highlighted in Vim.
def GetStringLabelHighlight(text: string, label: string): dict<number>
  var result = {hllen: 0, startcol: 0}

  result.hllen = label->len()
  result.startcol = text->stridx(label)
  if result.startcol < 0
    result.hllen = 0
    result.startcol = 0
  endif

  return result
enddef

# Helper function to convert LSP UTF-16 offsets to Vim byte indices.
def GetByteOffsets(text: string, start_utf16: number, end_utf16: number): dict<number>
  var result = {start: 0, len: 0}

  if has('patch-9.0.1629')
    # Modern Vim: Use native UTF-16 aware byteidx
    var start_byte = text->byteidx(start_utf16, true)
    var end_byte = text->byteidx(end_utf16, true)

    if start_byte >= 0 && end_byte > start_byte
      result.start = start_byte
      result.len = end_byte - start_byte
    endif
  else
    # Legacy/Compatibility: Fallback to raw offsets as byte positions
    # Note: This may misalign on non-ASCII characters in older versions
    result.start = start_utf16
    result.len = end_utf16 - start_utf16
  endif

  return result
enddef

# Convert a UTF-16 label-offset pair into a Vim byte-range highlight.
def GetOffsetLabelHighlight(text: string, labelOffset: list<any>): dict<number>
  var result = {hllen: 0, startcol: 0}

  if labelOffset->len() < 2 ||
      labelOffset[0]->type() != v:t_number ||
      labelOffset[1]->type() != v:t_number
    return result
  endif

  var start_offset: number = labelOffset[0]
  var end_offset: number = labelOffset[1]
  if start_offset < 0 || end_offset <= start_offset
    return result
  endif

  var offsets = GetByteOffsets(text, start_offset, end_offset)
  result.startcol = offsets.start
  result.hllen = offsets.len

  return result
enddef

def GetParameterHighlight(sig: dict<any>, text: string, activeParam: number): dict<number>
  var result = {hllen: 0, startcol: 0}

  # -1 means the server sent null activeParameter: suppress the highlight.
  if activeParam < 0
    return result
  endif

  var paramCount = GetSignatureParameterCount(sig)
  if paramCount == 0
    return result
  endif

  var params: list<dict<any>> = sig.parameters
  if activeParam >= paramCount
    return result
  endif

  var paramInfo: dict<any> = params[activeParam]
  var label: any = paramInfo.label
  if label->type() == v:t_string
    # Some servers return a string label that does not appear verbatim in the
    # rendered signature text. In that case, skip highlighting.
    return GetStringLabelHighlight(text, label)
  elseif label->type() == v:t_list
    # label is [inclusive start offset, exclusive end offset].
    return GetOffsetLabelHighlight(text, label)
  endif

  return result
enddef

# Return the currently selected signature, or {} when state is invalid.
def GetCurrentSignature(): dict<any>
  if sig_state.signatures->empty() || sig_state.index >= sig_state.signatures->len()
    return {}
  endif

  return sig_state.signatures[sig_state.index]
enddef

# Render signature text in the command line with active-parameter highlight.
def EchoSignature(text: string, hlinfo: dict<number>, docSummary: string)
  # Clear any leftover command-line text: "\r\r" moves to column 0 and the
  # empty echon flushes pending output before printing the new signature.
  :echon "\r\r"
  :echon ''
  :echon text->strpart(0, hlinfo.startcol)
  :echoh LspSigActiveParameter
  :echon text->strpart(hlinfo.startcol, hlinfo.hllen)
  :echoh None
  :echon text->strpart(hlinfo.startcol + hlinfo.hllen)
  if !docSummary->empty()
    :echoh Comment
    :echon '  ' .. docSummary
    :echoh None
  endif
enddef

# When lspgfm is applied to the popup buffer, markdown rendering can rewrite
# line 1 content. Restore the raw signature text and clear markdown props so
# parameter highlighting columns remain stable.
def RestoreSignatureFirstLine(bnr: number, signatureText: string)
  setbufline(bnr, 1, signatureText)
  prop_clear(1, 1, {bufnr: bnr})
enddef

# Render signature help in a popup and apply active-parameter text property.
def ShowPopupSignature(lspserver: dict<any>, lines: list<string>, hlinfo: dict<number>, total: number,
		       filetype: string)
  # Close the previous signature popup and open a new one
  if lspserver.signaturePopup != -1
    popup_close(lspserver.signaturePopup, SIG_POPUP_CLOSE_INTERNAL)
  endif

  var popupAttrs = opt.PopupConfigure('SignatureHelp', {
    padding: [0, 1, 0, 1],
    moved: [col('.') - 1, 9999999],
    pos: 'botright',
    callback: (id, result) => SignaturePopupCloseCb(lspserver, id, result)
  })
  var popupID = lines->popup_atcursor(popupAttrs)
  var bnr: number = popupID->winbufnr()
  if !filetype->empty()
    win_execute(popupID, $'setlocal ft={filetype}')
    RestoreSignatureFirstLine(bnr, lines[0])
  endif
  prop_type_add('signature', {bufnr: bnr, highlight: 'LspSigActiveParameter'})
  if hlinfo.hllen > 0
    prop_add(1, hlinfo.startcol + 1, {bufnr: bnr, length: hlinfo.hllen, type: 'signature'})
  endif
  lspserver.signaturePopup = popupID
  EnableSignatureSessionAutocmds()
enddef

# Render the current signature session either in the command line or in a
# popup. Popup mode also owns the temporary overload-navigation mappings.
def DisplayCurrentSignature(): void
  var sig: dict<any> = GetCurrentSignature()
  if sig->empty()
    return
  endif

  var lspserver: dict<any> = sig_state.lspserver
  var total = sig_state.signatures->len()
  var activeParam = GetCurrentActiveParameter()
  var display = GetSignatureDisplayInfo(lspserver, sig, sig_state.index, total,
				       activeParam)
  var hlinfo = GetParameterHighlight(sig, display.text, activeParam)

  if opt.lspOptions.echoSignature
    EchoSignature(display.text, hlinfo, display.docSummary)
  else
    ShowPopupSignature(lspserver, display.lines, hlinfo, total, display.filetype)
  endif
enddef

# -----------------------------------------------------------------------------
# Setup And Entry Points
# -----------------------------------------------------------------------------

# Register a per-buffer insert mapping for a trigger character.
# Only used in older vim versions without the KeyInputPre autocmd support.
def MapSignatureTriggerCharacter(ch: string)
  var mapChar = ch
  if ch =~ ' '
    mapChar = '<Space>'
  endif
  exe $"inoremap <buffer> <silent> {mapChar} {mapChar}<C-R>=g:LspShowSignatureTriggerChar({string(ch)})<CR>"
enddef

# Add or replace a buffer-local signature autocmd in the shared group.
def AddSignatureAutocmd(event: string, cmd: string)
  autocmd_add([{bufnr: bufnr(),
		group: 'LspSignatureHelp',
		event: event,
		replace: true,
		cmd: cmd}])
enddef

# Vim 9.1.0563+ supports KeyInputPre for trigger-char detection.
def HasKeyInputPreSupport(): bool
  return v:version > 901 || (v:version == 901 && has('patch0563'))
enddef

# Configure initial trigger-character detection using mappings or KeyInputPre.
def SetupSignatureTriggerChars(lspserver: dict<any>, autoTriggerChars: list<string>)
  if !HasKeyInputPreSupport()
    for ch in autoTriggerChars
      MapSignatureTriggerCharacter(ch)
    endfor
    return
  endif

  if !autoTriggerChars->empty()
    # detect the trigger chars and show the signature
    var cmd =<< trim eval END
      if index({lspserver.caps.signatureHelpProvider.triggerCharacters}, v:char) != -1
        call g:LspHandleSignatureTriggerChar(v:char)
      endif
    END
    AddSignatureAutocmd('KeyInputPre', cmd->join(' | '))
  endif
enddef

# Register retrigger and teardown autocmds for an active popup session.
def EnableSignatureSessionAutocmds()
  AddSignatureAutocmd('CursorMovedI', 'g:LspHandleSignatureContentChange()')
  AddSignatureAutocmd('TextChangedI', 'g:LspHandleSignatureContentChange()')
  AddSignatureAutocmd('InsertLeave', 'CloseCurBufSignaturePopup()')
enddef

# Remove popup-session autocmds when the signature popup is no longer visible.
def DisableSignatureSessionAutocmds()
  var bnr = sig_state.bnr
  if bnr < 0
    bnr = bufnr()
  endif
  autocmd_delete([{bufnr: bnr, group: 'LspSignatureHelp', event: 'CursorMovedI'}])
  autocmd_delete([{bufnr: bnr, group: 'LspSignatureHelp', event: 'TextChangedI'}])
  # Close the signature popup when leaving insert mode
  autocmd_delete([{bufnr: bnr, group: 'LspSignatureHelp', event: 'InsertLeave'}])
enddef

# Return true when server reply has at least one signature entry.
def HasValidSignatureHelpReply(sighelp: any): bool
  if sighelp->empty() || !sighelp->has_key('signatures')
    return false
  endif

  return sighelp.signatures->len() > 0
enddef

# Resolve active signature index from reply and clamp to bounds.
def GetReplySignatureIndex(sighelp: any, total: number): number
  var idx = 0
  if sighelp->has_key('activeSignature')
    var activeSig = sighelp.activeSignature
    if activeSig->type() == v:t_number && activeSig >= 0
      idx = activeSig
    endif
  endif

  # Per LSP 3.17 spec: if activeSignature is outside the array range,
  # treat it as 0 (the first signature).
  if idx > total - 1
    idx = 0
  endif

  return idx
enddef

# Extract the top-level SignatureHelp.activeParameter for storage in
# sig_state. Per-signature overrides are applied dynamically by
# GetCurrentActiveParameter so they are re-evaluated on each navigation.
def GetReplyActiveParameter(sighelp: any): number
  if sighelp->has_key('activeParameter')
    return NormalizeOptionalActiveParameter(sighelp.activeParameter)
  endif

  return 0
enddef

# Replace current signature session state from server reply.
def UpdateSignatureStateFromReply(lspserver: dict<any>, sighelp: any,
				  reqctx: dict<number> = {})
  sig_state.signatures = sighelp.signatures
  sig_state.lspserver = lspserver
  sig_state.bnr = reqctx->empty() ? bufnr() : reqctx.bnr
  sig_state.index = GetReplySignatureIndex(sighelp, sig_state.signatures->len())
  sig_state.activeParam = GetReplyActiveParameter(sighelp)
enddef

# Initialize one-time highlight groups used by signature rendering.
export def InitOnce()
  hlset([{name: 'LspSigActiveParameter', default: true, linksto: 'LineNr'}])
enddef

# Initialize signature trigger mappings/autocmds for the current buffer.
export def BufferInit(lspserver: dict<any>)
  if !lspserver.isSignatureHelpProvider
    # no support for signature help
    return
  endif

  if !opt.lspOptions.showSignature
      || !lspserver.featureEnabled('signatureHelp')
    # Show signature support is disabled
    return
  endif

  var autoTriggerChars = GetAutoSignatureTriggerCharacters(lspserver)
  SetupSignatureTriggerChars(lspserver, autoTriggerChars)
enddef

# process the 'textDocument/signatureHelp' reply from the LSP server and
# display the symbol signature help.
# Result: SignatureHelp | null
export def SignatureHelp(lspserver: dict<any>, sighelp: any,
			 reqctx: dict<number> = {}): void
  if !reqctx->empty() && !SignatureRequestContextMatches(reqctx)
    return
  endif

  if !HasValidSignatureHelpReply(sighelp)
    CloseSignaturePopup(lspserver)
    return
  endif

  # Replace the active signature session with the latest server reply so the
  # popup and overload navigation always reflect the current cursor context.
  UpdateSignatureStateFromReply(lspserver, sighelp, reqctx)

  DisplayCurrentSignature()
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
