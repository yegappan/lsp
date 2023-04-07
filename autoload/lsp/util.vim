vim9script

# Display a warning message
export def WarnMsg(msg: string)
  :echohl WarningMsg
  :echomsg msg
  :echohl None
enddef

# Display an error message
export def ErrMsg(msg: string)
  :echohl Error
  :echomsg msg
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
    writefile([msg], $'{lsp_log_dir}{fname}', 'a')
  endif
enddef

# Empty out the LSP server trace logs
export def ClearTraceLogs(fname: string)
  writefile([], fname)
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

# Convert a LSP file URI (file://<absolute_path>) to a Vim file name
export def LspUriToFile(uri: string): string
  # Replace all the %xx numbers (e.g. %20 for space) in the URI to character
  var uri_decoded: string = substitute(uri, '%\(\x\x\)',
				'\=nr2char(str2nr(submatch(1), 16))', 'g')

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
  return uri =~# '^\w\+::' || uri =~# '^[a-z][a-z0-9+.-]*://'
enddef

# Convert a Vim filename to an LSP URI (file://<absolute_path>)
export def LspFileToUri(fname: string): string
  var uri: string = fname->fnamemodify(':p')

  var on_windows: bool = false
  if uri =~? '^\a:'
    on_windows = true
  endif

  if on_windows
    # MS-Windows
    uri = uri->substitute('\\', '/', 'g')
  endif

  uri = uri->substitute('\([^A-Za-z0-9-._~:/]\)',
			'\=printf("%%%02x", char2nr(submatch(1)))', 'g')

  if on_windows
    uri = $'file:///{uri}'
  else
    uri = $'file://{uri}'
  endif

  return uri
enddef

# Convert a Vim buffer number to an LSP URI (file://<absolute_path>)
export def LspBufnrToUri(bnr: number): string
  return LspFileToUri(bnr->bufname())
enddef

# Returns the byte number of the specified LSP position in buffer 'bnr'.
# LSP's line and characters are 0-indexed.
# Vim's line and columns are 1-indexed.
# Returns a zero-indexed column.
export def GetLineByteFromPos(bnr: number, pos: dict<number>): number
  var col: number = pos.character
  # When on the first character, we can ignore the difference between byte and
  # character
  if col > 0
    # Need a loaded buffer to read the line and compute the offset
    if !bnr->bufloaded()
      bnr->bufload()
    endif

    var ltext: list<string> = bnr->getbufline(pos.line + 1)
    if !ltext->empty()
      var bidx = ltext[0]->byteidx(col)
      if bidx != -1
	return bidx
      endif
    endif
  endif

  return col
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

# Jump to the LSP 'location'.  The 'location' contains the file name, line
# number and character number. The user specified window command modifiers
# (e.g. topleft) are in 'cmdmods'.
export def JumpToLspLocation(location: dict<any>, cmdmods: string)
  var [uri, range] = LspLocationParse(location)
  var fname = LspUriToFile(uri)

  # jump to the file and line containing the symbol
  if cmdmods == ''
    var bnr: number = fname->bufnr()
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
    exe $'{cmdmods} split {fname}'
  endif
  setcursorcharpos(range.start.line + 1, range.start.character + 1)
enddef

# 'indexof' is to new to use it, use this instead.
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
# list of names in 'files' starting with the directory 'startDir'.
# Based on a similar implementation in the vim-lsp plugin.
# Searches upwards starting with the directory 'startDir'.
# If a file name ends with '/' or '\', then it is a directory name, otherwise
# it is a file name.
# Returns '' if none of the file and directory names in 'files' can be found
# in one of the parent directories.
export def FindNearestRootDir(startDir: string, files: list<any>): string
  var foundDirs: dict<bool> = {}

  for file in files
    if file->type() != v:t_string || file == ''
      continue
    endif
    var isDir = file[-1 : ] ==# '/' || file[-1 : ] ==# '\'
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

  # choose the longest matching path (the nearest directory from 'startDir')
  return sortedList[0]
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
