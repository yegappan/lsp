vim9script

import './util.vim'

# sort the list of edit operations in the descending order of line and column
# numbers.
# 'a': {'A': [lnum, col], 'B': [lnum, col]}
# 'b': {'A': [lnum, col], 'B': [lnum, col]}
def Edit_sort_func(a: dict<any>, b: dict<any>): number
  # line number
  if a.A[0] != b.A[0]
    return b.A[0] - a.A[0]
  endif
  # column number
  if a.A[1] != b.A[1]
    return b.A[1] - a.A[1]
  endif

  # Assume that the LSP sorted the lines correctly to begin with
  return b.idx - a.idx
enddef

# Replaces text in a range with new text.
#
# CAUTION: Changes in-place!
#
# 'lines': Original list of strings
# 'A': Start position; [line, col]
# 'B': End position [line, col]
# 'new_lines' A list of strings to replace the original
#
# returns the modified 'lines'
def Set_lines(lines: list<string>, A: list<number>, B: list<number>,
					new_lines: list<string>): list<string>
  var i_0: number = A[0]

  # If it extends past the end, truncate it to the end. This is because the
  # way the LSP describes the range including the last newline is by
  # specifying a line number after what we would call the last line.
  var numlines: number = lines->len()
  var i_n = [B[0], numlines - 1]->min()

  if i_0 < 0 || i_0 >= numlines || i_n < 0 || i_n >= numlines
    #util.WarnMsg("set_lines: Invalid range, A = " .. A->string()
    #		.. ", B = " ..  B->string() .. ", numlines = " .. numlines
    #		.. ", new lines = " .. new_lines->string())
    var msg = $"set_lines: Invalid range, A = {A->string()}"
    msg ..= $", B = {B->string()}, numlines = {numlines}"
    msg ..= $", new lines = {new_lines->string()}"
    util.WarnMsg(msg)
    return lines
  endif

  # save the prefix and suffix text before doing the replacements
  var prefix: string = ''
  var suffix: string = lines[i_n][B[1] :]
  if A[1] > 0
    prefix = lines[i_0][0 : A[1] - 1]
  endif

  var new_lines_len: number = new_lines->len()

  #echomsg $"i_0 = {i_0}, i_n = {i_n}, new_lines = {string(new_lines)}"
  var n: number = i_n - i_0 + 1
  if n != new_lines_len
    if n > new_lines_len
      # remove the deleted lines
      lines->remove(i_0, i_0 + n - new_lines_len - 1)
    else
      # add empty lines for newly the added lines (will be replaced with the
      # actual lines below)
      lines->extend(repeat([''], new_lines_len - n), i_0)
    endif
  endif
  #echomsg $"lines(1) = {string(lines)}"

  # replace the previous lines with the new lines
  for i in new_lines_len->range()
    lines[i_0 + i] = new_lines[i]
  endfor
  #echomsg $"lines(2) = {string(lines)}"

  # append the suffix (if any) to the last line
  if suffix != ''
    var i = i_0 + new_lines_len - 1
    lines[i] = lines[i] .. suffix
  endif
  #echomsg $"lines(3) = {string(lines)}"

  # prepend the prefix (if any) to the first line
  if prefix != ''
    lines[i_0] = prefix .. lines[i_0]
  endif
  #echomsg $"lines(4) = {string(lines)}"

  return lines
enddef

# Apply set of text edits to the specified buffer
# The text edit logic is ported from the Neovim lua implementation
export def ApplyTextEdits(bnr: number, text_edits: list<dict<any>>): void
  if text_edits->empty()
    return
  endif

  # if the buffer is not loaded, load it and make it a listed buffer
  :silent! bnr->bufload()
  setbufvar(bnr, '&buflisted', true)

  var start_line: number = 4294967295		# 2 ^ 32
  var finish_line: number = -1
  var updated_edits: list<dict<any>> = []
  var start_row: number
  var start_col: number
  var end_row: number
  var end_col: number

  # create a list of buffer positions where the edits have to be applied.
  var idx = 0
  for e in text_edits
    # Adjust the start and end columns for multibyte characters
    var r = e.range
    var rstart: dict<any> = r.start
    var rend: dict<any> = r.end
    start_row = rstart.line
    start_col = util.GetCharIdxWithoutCompChar(bnr, rstart)
    end_row = rend.line
    end_col = util.GetCharIdxWithoutCompChar(bnr, rend)
    start_line = [rstart.line, start_line]->min()
    finish_line = [rend.line, finish_line]->max()

    updated_edits->add({A: [start_row, start_col],
			B: [end_row, end_col],
                        idx: idx,
			lines: e.newText->split("\n", true)})
    idx += 1
  endfor

  # Reverse sort the edit operations by descending line and column numbers so
  # that they can be applied without interfering with each other.
  updated_edits->sort('Edit_sort_func')

  var lines: list<string> = bnr->getbufline(start_line + 1, finish_line + 1)
  var fix_eol: bool = bnr->getbufvar('&fixeol')
  var set_eol = fix_eol && bnr->getbufinfo()[0].linecount <= finish_line + 1
  if !lines->empty() && set_eol && lines[-1]->len() != 0
    lines->add('')
  endif

  #echomsg $'lines(1) = {string(lines)}'
  #echomsg updated_edits

  for e in updated_edits
    var A: list<number> = [e.A[0] - start_line, e.A[1]]
    var B: list<number> = [e.B[0] - start_line, e.B[1]]
    lines = Set_lines(lines, A, B, e.lines)
  endfor

  #echomsg $'lines(2) = {string(lines)}'

  # If the last line is empty and we need to set EOL, then remove it.
  if !lines->empty() && set_eol && lines[-1]->len() == 0
    lines->remove(-1)
  endif

  #echomsg $'ApplyTextEdits: start_line = {start_line}, finish_line = {finish_line}'
  #echomsg $'lines = {string(lines)}'

  # if the buffer is empty, appending lines before the first line adds an
  # extra empty line at the end. Delete the empty line after appending the
  # lines.
  var dellastline: bool = false
  if start_line == 0 && bnr->getbufinfo()[0].linecount == 1 &&
					bnr->getbufline(1)->get(0, '')->empty()
    dellastline = true
  endif

  # Now we apply the textedits to the actual buffer.
  # In theory we could just delete all old lines and append the new lines.
  # This would however cause the cursor to change position: It will always be
  # on the last line added.
  #
  # Luckily there is an even simpler solution, that has no cursor sideeffects.
  #
  # Logically this method is split into the following three cases:
  #
  # 1. The number of new lines is equal to the number of old lines:
  #    Just replace the lines inline with setbufline()
  #
  # 2. The number of new lines is greater than the old ones:
  #    First append the missing lines at the **end** of the range, then use
  #    setbufline() again. This does not cause the cursor to change position.
  #
  # 3. The number of new lines is less than before:
  #    First use setbufline() to replace the lines that we can replace.
  #    Then remove superfluous lines.
  #
  # Luckily, the three different cases exist only logically, we can reduce
  # them to a single case practically, because appendbufline() does not append
  # anything if an empty list is passed just like deletebufline() does not
  # delete anything, if the last line of the range is before the first line.
  # We just need to be careful with all indices.
  appendbufline(bnr, finish_line + 1, lines[finish_line - start_line + 1 : -1])
  setbufline(bnr, start_line + 1, lines)
  deletebufline(bnr, start_line + 1 + lines->len(), finish_line + 1)

  if dellastline
    bnr->deletebufline(bnr->getbufinfo()[0].linecount)
  endif
enddef

# interface TextDocumentEdit
def ApplyTextDocumentEdit(textDocEdit: dict<any>)
  var bnr: number = util.LspUriToBufnr(textDocEdit.textDocument.uri)
  if bnr == -1
    util.ErrMsg($'Text Document edit, buffer {textDocEdit.textDocument.uri} is not found')
    return
  endif
  ApplyTextEdits(bnr, textDocEdit.edits)
enddef

# interface CreateFile
# Create the "createFile.uri" file
def FileCreate(createFile: dict<any>)
  var fname: string = util.LspUriToFile(createFile.uri)
  var opts: dict<bool> = createFile->get('options', {})
  var ignoreIfExists: bool = opts->get('ignoreIfExists', true)
  var overwrite: bool = opts->get('overwrite', false)

  # LSP Spec: Overwrite wins over `ignoreIfExists`
  if fname->filereadable() && ignoreIfExists && !overwrite
    return
  endif

  fname->fnamemodify(':p:h')->mkdir('p')
  []->writefile(fname)
  fname->bufadd()
enddef

# interface DeleteFile
# Delete the "deleteFile.uri" file
def FileDelete(deleteFile: dict<any>)
  var fname: string = util.LspUriToFile(deleteFile.uri)
  var opts: dict<bool> = deleteFile->get('options', {})
  var recursive: bool = opts->get('recursive', false)
  var ignoreIfNotExists: bool = opts->get('ignoreIfNotExists', true)

  if !fname->filereadable() && ignoreIfNotExists
    return
  endif

  var flags: string = ''
  if recursive
    # # NOTE: is this a dangerous operation?  The LSP server can send a
    # # DeleteFile message to recursively delete all the files in the disk.
    # flags = 'rf'
    util.ErrMsg($'Recursively deleting files is not supported')
    return
  elseif fname->isdirectory()
    flags = 'd'
  endif
  var bnr: number = fname->bufadd()
  fname->delete(flags)
  exe $'{bnr}bwipe!'
enddef

# interface RenameFile
# Rename file "renameFile.oldUri" to "renameFile.newUri"
def FileRename(renameFile: dict<any>)
  var old_fname: string = util.LspUriToFile(renameFile.oldUri)
  var new_fname: string = util.LspUriToFile(renameFile.newUri)

  var opts: dict<bool> = renameFile->get('options', {})
  var overwrite: bool = opts->get('overwrite', false)
  var ignoreIfExists: bool = opts->get('ignoreIfExists', true)

  if new_fname->filereadable() && (!overwrite || ignoreIfExists)
    return
  endif

  old_fname->rename(new_fname)
enddef

# interface WorkspaceEdit
export def ApplyWorkspaceEdit(workspaceEdit: dict<any>)
  if workspaceEdit->has_key('documentChanges')
    for change in workspaceEdit.documentChanges
      if change->has_key('kind')
	if change.kind == 'create'
	  FileCreate(change)
	elseif change.kind == 'delete'
	  FileDelete(change)
	elseif change.kind == 'rename'
	  FileRename(change)
	else
	  util.ErrMsg($'Unsupported change in workspace edit [{change.kind}]')
	endif
      else
	ApplyTextDocumentEdit(change)
      endif
    endfor
    return
  endif

  if !workspaceEdit->has_key('changes')
    return
  endif

  for [uri, changes] in workspaceEdit.changes->items()
    var bnr: number = util.LspUriToBufnr(uri)
    if bnr == 0
      # file is not present
      continue
    endif

    # interface TextEdit
    ApplyTextEdits(bnr, changes)
  endfor
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
