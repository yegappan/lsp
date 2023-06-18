vim9script

import './util.vim'

# Functions for encoding and decoding the LSP position offsets.  Language
# servers support either UTF-8 or UTF-16 or UTF-32 position offsets.  The
# character related Vim functions use the UTF-32 position offset.  The
# encoding used is negotiated during the language server initialization.

# Encode the UTF-32 character offset in the LSP position "pos" to the encoding
# negotiated with the language server.
#
# Modifies in-place the UTF-32 offset in pos.character to a UTF-8 or UTF-16 or
# UTF-32 offset.
export def EncodePosition(lspserver: dict<any>, bnr: number, pos: dict<number>)
  if has('patch-9.0.1629')
    if lspserver.posEncoding == 32 || bnr <= 0
      # LSP client plugin also uses utf-32 encoding
      return
    endif

    :silent! bnr->bufload()
    var text = bnr->getbufline(pos.line + 1)->get(0, '')
    if text->empty()
      return
    endif

    if lspserver.posEncoding == 16
      pos.character = text->utf16idx(pos.character, true, true)
    else
      pos.character = text->byteidxcomp(pos.character)
    endif
  endif
enddef

# Decode the character offset in the LSP position "pos" using the encoding
# negotiated with the language server to a UTF-32 offset.
#
# Modifies in-place the UTF-8 or UTF-16 or UTF-32 offset in pos.character to a
# UTF-32 offset.
export def DecodePosition(lspserver: dict<any>, bnr: number, pos: dict<number>)
  if has('patch-9.0.1629')
    if lspserver.posEncoding == 32 || bnr <= 0
      # LSP client plugin also uses utf-32 encoding
      return
    endif

    :silent! bnr->bufload()
    var text = bnr->getbufline(pos.line + 1)->get(0, '')
    # If the line is empty then don't decode the character position.
    if text->empty()
      return
    endif

    # If the character position is out-of-bounds, then don't decode the
    # character position.
    var textLen = 0
    if lspserver.posEncoding == 16
      textLen = text->strutf16len(true)
    else
      textLen = text->strlen()
    endif

    if pos.character > textLen
      return
    endif

    if pos.character == textLen
      pos.character = text->strchars()
    else
      if lspserver.posEncoding == 16
	pos.character = text->charidx(pos.character, true, true)
      else
	pos.character = text->charidx(pos.character, true)
      endif
    endif
  endif
enddef

# Encode the start and end UTF-32 character offsets in the LSP range "range"
# to the encoding negotiated with the language server.
#
# Modifies in-place the UTF-32 offset in range.start.character and
# range.end.character to a UTF-8 or UTF-16 or UTF-32 offset.
export def EncodeRange(lspserver: dict<any>, bnr: number,
		       range: dict<dict<number>>)
  if has('patch-9.0.1629')
    if lspserver.posEncoding == 32
      return
    endif

    EncodePosition(lspserver, bnr, range.start)
    EncodePosition(lspserver, bnr, range.end)
  endif
enddef

# Decode the start and end character offsets in the LSP range "range" to
# UTF-32 offsets.
#
# Modifies in-place the offset value in range.start.character and
# range.end.character to a UTF-32 offset.
export def DecodeRange(lspserver: dict<any>, bnr: number,
		       range: dict<dict<number>>)
  if has('patch-9.0.1629')
    if lspserver.posEncoding == 32
      return
    endif

    DecodePosition(lspserver, bnr, range.start)
    DecodePosition(lspserver, bnr, range.end)
  endif
enddef

# Encode the range in the LSP position "location" to the encoding negotiated
# with the language server.
#
# Modifies in-place the UTF-32 offset in location.range to a UTF-8 or UTF-16
# or UTF-32 offset.
export def EncodeLocation(lspserver: dict<any>, location: dict<any>)
  if has('patch-9.0.1629')
    if lspserver.posEncoding == 32
      return
    endif

    var bnr = 0
    if location->has_key('targetUri')
      # LocationLink
      bnr = util.LspUriToBufnr(location.targetUri)
      if bnr > 0
	# We use only the "targetSelectionRange" item.  The
	# "originSelectionRange" and the "targetRange" items are not used.
	lspserver.encodeRange(bnr, location.targetSelectionRange)
      endif
    else
      # Location
      bnr = util.LspUriToBufnr(location.uri)
      if bnr > 0
	lspserver.encodeRange(bnr, location.range)
      endif
    endif
  endif
enddef

# Decode the range in the LSP location "location" to UTF-32.
#
# Modifies in-place the offset value in location.range to a UTF-32 offset.
export def DecodeLocation(lspserver: dict<any>, location: dict<any>)
  if has('patch-9.0.1629')
    if lspserver.posEncoding == 32
      return
    endif

    var bnr = 0
    if location->has_key('targetUri')
      # LocationLink
      bnr = util.LspUriToBufnr(location.targetUri)
      # We use only the "targetSelectionRange" item.  The
      # "originSelectionRange" and the "targetRange" items are not used.
      lspserver.decodeRange(bnr, location.targetSelectionRange)
    else
      # Location
      bnr = util.LspUriToBufnr(location.uri)
      lspserver.decodeRange(bnr, location.range)
    endif
  endif
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
