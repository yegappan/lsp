vim9script

# Display an info message
export def InfoMsg(msg: string)
  :echohl Question
  :echomsg $'Info: {msg}'
  :echohl None
enddef

# Display a warning message
export def WarnMsg(msg: string)
  :echohl WarningMsg
  :echomsg $'Warn: {msg}'
  :echohl None
enddef

# Display an error message
export def ErrMsg(msg: string)
  :echohl Error
  :echomsg $'Error: {msg}'
  :echohl None
enddef

# Lsp server trace log directory
var lsp_log_dir: string
if has('unix')
  lsp_log_dir = '/tmp/'
else
  lsp_log_dir = $TEMP .. '\\'
endif

# Log a message from the LSP server. stderr is true for logging messages
# from the standard error and false for stdout.
export def TraceLog(fname: string, stderr: bool, msg: string)
  if stderr
    writefile(msg->split("\n"), $'{lsp_log_dir}{fname}', 'a')
  else
    writefile([$'{strftime("%m/%d/%y %T")}: {msg}'], $'{lsp_log_dir}{fname}', 'a')
  endif
enddef

# Empty out the LSP server trace logs
export def ClearTraceLogs(fname: string)
  writefile([], $'{lsp_log_dir}{fname}')
enddef

# Open the LSP server debug messages file.
export def ServerMessagesShow(fname: string)
  var fullname = $'{lsp_log_dir}{fname}'
  if !filereadable(fullname)
    WarnMsg($'File {fullname} is not found')
    return
  endif
  var wid = fullname->bufwinid()
  if wid == -1
    exe $'split {fullname}'
  else
    win_gotoid(wid)
  endif
  setlocal autoread
  setlocal bufhidden=wipe
  setlocal nomodified
  setlocal nomodifiable
enddef

# Parse a LSP Location or LocationLink type and return a List with two items.
# The first item is the DocumentURI and the second item is the Range.
export def LspLocationParse(lsploc: dict<any>): list<any>
  if lsploc->has_key('targetUri')
    # LocationLink
    return [lsploc.targetUri, lsploc.targetSelectionRange]
  else
    # Location
    return [lsploc.uri, lsploc.range]
  endif
enddef

# A 2-character string match the hex format
def IsHex(str: string): bool
    if strlen(str) != 2
        return false
    endif
    return match(str, '^[A-Fa-f0-9]\{2}$') == 0
enddef

# convert hex string to unicode code point
# return unicode code point or -1
def HexStrToUnicodeCodePoint(str: string): number
    var byte_values: list<number> = []
    for hex in str->split('%') 
        if !IsHex(hex)
            return -1
        endif
        byte_values->add(str2nr(hex, 16))
    endfor

    if len(byte_values) > 1
        for value in byte_values[1 :]
            if value < 128 || value >= 192
                return -1
            endif
        endfor
    endif

    # 1-byte utf8 character
    if (byte_values[0] >= 0 && byte_values[0] < 128) && len(byte_values) == 1
        return byte_values[0]
    endif
    # 2-bytes utf8 character
    if (byte_values[0] >= 192 && byte_values[0] < 224) && len(byte_values) == 2
        return (and(31, byte_values[0]) << 6) + (and(63, byte_values[1]))
    endif
    # 3-bytes utf8 character
    if (byte_values[0] >= 224 && byte_values[0] < 240) && len(byte_values) == 3
        return (and(15, byte_values[0]) << 12) + (and(63, byte_values[1]) << 6) + and(63, byte_values[2])
    endif
    # 4-bytes utf8 character
    if (byte_values[0] >= 240 && byte_values[0] < 248) && len(byte_values) == 4
        return (and(7, byte_values[0]) << 18) + (and(63, byte_values[1]) << 12) + (and(63, byte_values[2]) << 6) + and(63, byte_values[3])
    endif
    return -1
enddef

# convert string to url encoding string
def UriEncode(str: string): string
    var encoded_str: string = ''
    for idx in range(strlen(str))
        var char = strpart(str, idx, 1)
        if char->match('[A-Za-z0-9-._~:/]') == -1
            encoded_str = encoded_str .. printf('%%%02X', char2nr(char))
        else
            encoded_str = encoded_str .. char
        endif
    endfor
    return encoded_str
enddef

# convert url encoding string to nroaml string
def UriDecode(str: string): string
    var decode_str: string = ''
    var idx: number = 0
    var slen: number = strlen(str)
    while idx < slen
        var char: string = strpart(str, idx, 1)
        if char == '%'
            if idx + 2 >= slen
                # no more characters
                decode_str ..= strpart(str, idx, slen - idx)
                break
            else
                var hexpart_1st: string = strpart(str, idx + 1, 2)
                if !IsHex(hexpart_1st)
                    decode_str ..= char
                    idx += 1
                    continue
                endif
                var utf8_value_1st: number = str2nr(hexpart_1st, 16)

                var idx_offset: number = 0
                var unicode_cp: number = -1

                if utf8_value_1st >= 0 && utf8_value_1st < 128
                    unicode_cp = HexStrToUnicodeCodePoint(strpart(str, idx, 3))
                    idx_offset = 3
                endif

                if utf8_value_1st >= 192 && utf8_value_1st < 224
                    if idx + 5 >= slen
                        decode_str ..= char
                        idx += 1
                        continue
                    endif
                    unicode_cp = HexStrToUnicodeCodePoint(strpart(str, idx, 6))
                    idx_offset = 6
                endif

                if utf8_value_1st >= 224 && utf8_value_1st < 240
                    if idx + 8 >= slen
                        decode_str ..= char
                        idx += 1
                        continue
                    endif
                    unicode_cp = HexStrToUnicodeCodePoint(strpart(str, idx, 9))
                    idx_offset = 9
                endif

                if utf8_value_1st >= 240 && utf8_value_1st < 248
                    if idx + 11 >= slen
                        decode_str ..= char
                        idx += 1
                        continue
                    endif
                    unicode_cp = HexStrToUnicodeCodePoint(strpart(str, idx, 12))
                    idx_offset = 12
                endif

                if unicode_cp == -1
                    decode_str ..= char
                    idx += 1
                else
                    decode_str ..= nr2char(unicode_cp)
                    idx += idx_offset
                endif
            endif
        else
            decode_str ..= char
            idx += 1
        endif
    endwhile
    return decode_str
enddef


# Convert a LSP file URI (file://<absolute_path>) to a Vim file name
export def LspUriToFile(uri: string): string
  # Replace all the %xx numbers (e.g. %20 for space) in the URI to character
  var uri_decoded: string = UriDecode(uri)

  # File URIs on MS-Windows start with file:///[a-zA-Z]:'
  if uri_decoded =~? '^file:///\a:'
    # MS-Windows URI
    uri_decoded = uri_decoded[8 : ]
    uri_decoded = uri_decoded->substitute('/', '\\', 'g')
  # On GNU/Linux (pattern not end with `:`)
  elseif uri_decoded =~? '^file:///\a'
    uri_decoded = uri_decoded[7 : ]
  endif

  return uri_decoded
enddef

# Convert a LSP file URI (file://<absolute_path>) to a Vim buffer number.
# If the file is not in a Vim buffer, then adds the buffer.
# Returns 0 on error.
export def LspUriToBufnr(uri: string): number
  return LspUriToFile(uri)->bufadd()
enddef

# Returns if the URI refers to a remote file (e.g. ssh://)
# Credit: vim-lsp plugin
export def LspUriRemote(uri: string): bool
  return uri =~ '^\w\+::' || uri =~ '^[a-z][a-z0-9+.-]*://'
enddef

var resolvedUris = {}

# Convert a Vim filename to an LSP URI (file://<absolute_path>)
export def LspFileToUri(fname: string): string
  var fname_full: string = fname->fnamemodify(':p')

  if resolvedUris->has_key(fname_full)
    return resolvedUris[fname_full]
  endif

  var uri: string = fname_full

  if has("win32unix")
    # We're in Cygwin, convert POSIX style paths to Windows style.
    # The substitution is to remove the '^@' escape character from the end of
    # line.
    uri = system($'cygpath -m {uri}')->substitute('^\(\p*\).*$', '\=submatch(1)', "")
  endif

  var on_windows: bool = false
  if uri =~? '^\a:'
    on_windows = true
  endif

  if on_windows
    # MS-Windows
    uri = uri->substitute('\\', '/', 'g')
  endif

  uri = UriEncode(uri)

  if on_windows
    uri = $'file:///{uri}'
  else
    uri = $'file://{uri}'
  endif

  resolvedUris[fname_full] = uri
  return uri
enddef

# Convert a Vim buffer number to an LSP URI (file://<absolute_path>)
export def LspBufnrToUri(bnr: number): string
  return LspFileToUri(bnr->bufname())
enddef

# Returns the byte number of the specified LSP position in buffer "bnr".
# LSP's line and characters are 0-indexed.
# Vim's line and columns are 1-indexed.
# Returns a zero-indexed column.
export def GetLineByteFromPos(bnr: number, pos: dict<number>): number
  var col: number = pos.character
  # When on the first character, we can ignore the difference between byte and
  # character
  if col <= 0
    return col
  endif

  # Need a loaded buffer to read the line and compute the offset
  :silent! bnr->bufload()

  var ltext: string = bnr->getbufline(pos.line + 1)->get(0, '')
  if ltext->empty()
    return col
  endif

  var byteIdx = ltext->byteidxcomp(col)
  if byteIdx != -1
    return byteIdx
  endif

  return col
enddef

# Get the index of the character at [pos.line, pos.character] in buffer "bnr"
# without counting the composing characters.  The LSP server counts composing
# characters as separate characters whereas Vim string indexing ignores the
# composing characters.
export def GetCharIdxWithoutCompChar(bnr: number, pos: dict<number>): number
  var col: number = pos.character
  # When on the first character, nothing to do.
  if col <= 0
    return col
  endif

  # Need a loaded buffer to read the line and compute the offset
  :silent! bnr->bufload()

  var ltext: string = bnr->getbufline(pos.line + 1)->get(0, '')
  if ltext->empty()
    return col
  endif

  # Convert the character index that includes composing characters as separate
  # characters to a byte index and then back to a character index ignoring the
  # composing characters.
  var byteIdx = ltext->byteidxcomp(col)
  if byteIdx != -1
    if byteIdx == ltext->strlen()
      # Byte index points to the byte after the last byte.
      return ltext->strcharlen()
    else
      return ltext->charidx(byteIdx, false)
    endif
  endif

  return col
enddef

# Get the index of the character at [pos.line, pos.character] in buffer "bnr"
# counting the composing characters as separate characters.  The LSP server
# counts composing characters as separate characters whereas Vim string
# indexing ignores the composing characters.
export def GetCharIdxWithCompChar(ltext: string, charIdx: number): number
  # When on the first character, nothing to do.
  if charIdx <= 0 || ltext->empty()
    return charIdx
  endif

  # Convert the character index that doesn't include composing characters as
  # separate characters to a byte index and then back to a character index
  # that includes the composing characters as separate characters
  var byteIdx = ltext->byteidx(charIdx)
  if byteIdx != -1
    if byteIdx == ltext->strlen()
      return ltext->strchars()
    else
      return ltext->charidx(byteIdx, true)
    endif
  endif

  return charIdx
enddef

# push the current location on to the tag stack
export def PushCursorToTagStack()
  settagstack(winnr(), {items: [
			 {
			   bufnr: bufnr(),
			   from: getpos('.'),
			   matchnr: 1,
			   tagname: expand('<cword>')
			 }]}, 't')
enddef

# Jump to the LSP "location".  The "location" contains the file name, line
# number and character number. The user specified window command modifiers
# (e.g. topleft) are in "cmdmods".
export def JumpToLspLocation(location: dict<any>, cmdmods: string)
  var [uri, range] = LspLocationParse(location)
  var fname = LspUriToFile(uri)

  # jump to the file and line containing the symbol
  var bnr: number = fname->bufnr()
  if cmdmods->empty()
    if bnr == bufnr()
      # Set the previous cursor location mark. Instead of using setpos(), m' is
      # used so that the current location is added to the jump list.
      :normal m'
    else
      var wid = fname->bufwinid()
      if wid != -1
        wid->win_gotoid()
      else
        if bnr != -1
          # Reuse an existing buffer. If the current buffer has unsaved changes
          # and 'hidden' is not set or if the current buffer is a special
          # buffer, then open the buffer in a new window.
          if (&modified && !&hidden) || &buftype != ''
            exe $'belowright sbuffer {bnr}'
          else
            exe $'buf {bnr}'
          endif
	  # In case 'buflisted' is not yet set for this buffer, set it now
	  setlocal buflisted
        else
          if (&modified && !&hidden) || &buftype != ''
            # if the current buffer has unsaved changes and 'hidden' is not set,
            # or if the current buffer is a special buffer, then open the file
            # in a new window
            exe $'belowright split {fname}'
          else
            exe $'edit {fname}'
          endif
        endif
      endif
    endif
  else
    if bnr == -1
      exe $'{cmdmods} split {fname}'
    else
      # Use "sbuffer" so that the 'switchbuf' option settings are used.
      exe $'{cmdmods} sbuffer {bnr}'
    endif
  endif
  var rstart = range.start
  setcursorcharpos(rstart.line + 1,
		   GetCharIdxWithoutCompChar(bufnr(), rstart) + 1)
  :normal! zv
enddef

# indexof() function is not present in older Vim 9 versions.  So use this
# function.
export def Indexof(list: list<any>, CallbackFn: func(number, any): bool): number
  var ix = 0
  for val in list
    if CallbackFn(ix, val)
      return ix
    endif
    ix += 1
  endfor
  return -1
enddef

# Find the nearest root directory containing a file or directory name from the
# list of names in "files" starting with the directory "startDir".
# Based on a similar implementation in the vim-lsp plugin.
# Searches upwards starting with the directory "startDir".
# If a file name ends with '/' or '\', then it is a directory name, otherwise
# it is a file name.
# Returns '' if none of the file and directory names in "files" can be found
# in one of the parent directories.
export def FindNearestRootDir(startDir: string, files: list<any>): string
  var foundDirs: dict<bool> = {}

  for file in files
    if file->type() != v:t_string || file->empty()
      continue
    endif
    var isDir = file[-1 : ] == '/' || file[-1 : ] == '\'
    var relPath: string
    if isDir
      relPath = finddir(file, $'{startDir};')
    else
      relPath = findfile(file, $'{startDir};')
    endif
    if relPath->empty()
      continue
    endif
    var rootDir = relPath->fnamemodify(isDir ? ':p:h:h' : ':p:h')
    foundDirs[rootDir] = true
  endfor
  if foundDirs->empty()
    return ''
  endif

  # Sort the directory names by length
  var sortedList: list<string> = foundDirs->keys()->sort((a, b) => {
    return b->len() - a->len()
  })

  # choose the longest matching path (the nearest directory from "startDir")
  return sortedList[0]
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
