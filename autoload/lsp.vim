vim9script

# Vim LSP client

var lsp_servers: dict<dict<any>> = {}

var lsp_log_dir: string = '/tmp/'

# process the initialize reply from the LSP server
def lsp#processInitializeReply(ftype: string, reply: dict<any>): void
  if reply.result->len() <= 0
    return
  endif

  var caps: dict<any> = reply.result.capabilities
  lsp_servers[ftype].caps = caps
  if caps->has_key('signatureHelpProvider')
    var triggers = caps.signatureHelpProvider.triggerCharacters
    for ch in triggers
      exe 'inoremap <silent> ' .. ch .. ' ' .. ch .. "<C-R>=lsp#show_signature()<CR>"
    endfor
  endif
enddef

# process the 'textDocument/definition'/'textDocument/declaration' replies
# from the LSP server
def lsp#processDefDeclReply(reply: dict<any>): void
  if reply.result->len() == 0
    echomsg "Error: definition is not found"
    return
  endif

  var result: dict<any> = reply.result[0]
  var file = result.uri[7:]
  var wid = bufwinid(file)
  if wid != -1
    win_gotoid(wid)
  else
    exe 'split ' .. file
  endif
  cursor(result.range.start.line + 1, result.range.start.character + 1)
  redraw!
enddef

# process the signatureHelp reply from the LSP server
def lsp#process_signatureHelp_reply(reply: dict<any>): void
  var result: dict<any> = reply.result
  if result.signatures->len() <= 0
    return
  endif

  var sig: dict<any> = result.signatures[result.activeSignature]
  var text = sig.label
  var hllen = 0
  var startcol = 0
  var params_len = sig.parameters->len()
  if params_len > 0 && result.activeParameter < params_len
    var label = sig.parameters[result.activeParameter].label
    hllen = label->len()
    startcol = text->stridx(label)
  endif
  var popupID = popup_atcursor(text, {})
  prop_type_add('signature', {'bufnr': popupID->winbufnr(),
  'highlight': 'Title'})
  if hllen > 0
    prop_add(1, startcol + 1, {'bufnr': popupID->winbufnr(), 'length': hllen, 'type': 'signature'})
  endif
enddef

# Process varous reply messages from the LSP server
def lsp#process_reply(ftype: string, req: dict<any>, reply: dict<any>): void
  if req.method == 'initialize'
    lsp#processInitializeReply(ftype, reply)
  elseif req.method == 'textDocument/definition' || req.method == 'textDocument/declaration'
    lsp#processDefDeclReply(reply)
  elseif req.method == 'textDocument/signatureHelp'
    lsp#process_signatureHelp_reply(reply)
  endif
enddef

def lsp#process_server_msg(ftype: string): void
  while lsp_servers[ftype].data->len() > 0
    var idx = stridx(lsp_servers[ftype].data, 'Content-Length: ')
    if idx == -1
      return
    endif

    var len = str2nr(lsp_servers[ftype].data[idx + 16:])
    if len == 0
      echomsg "Error: Content length is zero"
      return
    endif

    # Header and contents are separated by '\r\n\r\n'
    idx = stridx(lsp_servers[ftype].data, "\r\n\r\n")
    if idx == -1
      echomsg "Error: Content separator is not found"
      return
    endif

    idx = idx + 4

    if lsp_servers[ftype].data->len() - idx < len
      echomsg "Error: Didn't receive the complete message"
      return
    endif

    var content = lsp_servers[ftype].data[idx : idx + len - 1]
    var reply = content->json_decode()

    if reply->has_key('id')
      var req = lsp_servers[ftype].requests->get(string(reply.id))
      # Remove the corresponding stored request message
      lsp_servers[ftype].requests->remove(string(reply.id))

      if reply->has_key('error')
        echomsg "Error: request " .. req.method .. " failed (" .. reply.error.message .. ")"
      else
        lsp#process_reply(ftype, req, reply)
      endif
    endif

    lsp_servers[ftype].data = lsp_servers[ftype].data[idx + len :]
  endwhile
enddef

def lsp#output_cb(ftype: string, chan: channel, msg: string): void
  writefile(split(msg, "\n"), lsp_log_dir .. 'lsp_server.out', 'a')
  lsp_servers[ftype].data = lsp_servers[ftype].data .. msg
  lsp#process_server_msg(ftype)
enddef

def lsp#error_cb(ftype: string, chan: channel, emsg: string,): void
  writefile(split(emsg, "\n"), lsp_log_dir .. 'lsp_server.err', 'a')
enddef

def lsp#exit_cb(ftype: string, job: job, status: number): void
  echomsg "LSP server exited with status " .. status
enddef

# Return the next id for a LSP server request message
def lsp#next_reqid(ftype: string): number
  var id = lsp_servers[ftype].nextID
  lsp_servers[ftype].nextID = id + 1
  return id
enddef

# Send a request message to LSP server
def lsp#sendto_server(ftype: string, content: dict<any>): void
  var req_js: string = content->json_encode()
  var msg = "Content-Length: " .. req_js->len() .. "\r\n\r\n"
  var ch = lsp_servers[ftype].job->job_getchannel()
  ch->ch_sendraw(msg)
  call writefile(["req_js length = " .. req_js->len()], "lsp_trace.txt", 'a')
  ch->ch_sendraw(req_js)
  call writefile(["After sending data"], "lsp_trace.txt", 'a')
enddef

def lsp#create_reqmsg(ftype: string, method: string): dict<any>
  var req = {}
  req.jsonrpc = '2.0'
  req.id = lsp#next_reqid(ftype)
  req.method = method
  req.params = {}

  # Save the request, so that the corresponding response can be processed
  lsp_servers[ftype].requests->extend({[string(req.id)]: req})

  return req
enddef

def lsp#create_notifmsg(ftype: string, notif: string): dict<any>
  var req = {}
  req.jsonrpc = '2.0'
  req.method = notif
  req.params = {}

  return req
enddef

# Send a "initialize" LSP request
def lsp#init_server(ftype: string): number
  var req = lsp#create_reqmsg(ftype, 'initialize')
  lsp#sendto_server(ftype, req)
  return 1
enddef

# Start a LSP server
def lsp#start_server(ftype: string): number
  if lsp_servers[ftype].running
    echomsg "LSP server for " .. ftype .. " is already running"
    return 0
  endif

  var cmd = [lsp_servers[ftype].path]
  cmd->extend(lsp_servers[ftype].args)

  var opts = {'in_mode': 'raw',
              'out_mode': 'raw',
              'err_mode': 'raw',
              'out_cb': function('lsp#output_cb', [ftype]),
              'err_cb': function('lsp#error_cb', [ftype]),
              'exit_cb': function('lsp#exit_cb', [ftype])}

  writefile([], lsp_log_dir .. 'lsp_server.out')
  writefile([], lsp_log_dir .. 'lsp_server.err')
  lsp_servers[ftype].data = ''
  lsp_servers[ftype].caps = {}
  lsp_servers[ftype].nextID = 1
  lsp_servers[ftype].requests = {}

  var job = job_start(cmd, opts)
  if job->job_status() == 'fail'
    echomsg "Error: Failed to start LSP server " .. lsp_servers[ftype].path
    return 1
  endif

  lsp_servers[ftype].job = job
  lsp_servers[ftype].running = v:true

  lsp#init_server(ftype)

  return 0
enddef

# Send a 'shutdown' request to the LSP server
def lsp#shutdown_server(ftype: string): void
  var req = lsp#create_reqmsg(ftype, 'shutdown')
  lsp#sendto_server(ftype, req)
enddef

# Send a 'exit' notification to the LSP server
def lsp#exit_server(ftype: string): void
  var req: dict<any> = lsp#create_notifmsg(ftype, 'exit')
  lsp#sendto_server(ftype, req)
enddef

# Stop a LSP server
def lsp#stop_server(ftype: string): number
  if !lsp_servers[ftype].running
    echomsg "LSP server for " .. ftype .. " is not running"
    return 0
  endif

  lsp#shutdown_server(ftype)

  # Wait for the server to process the shutodwn request
  sleep 1

  lsp#exit_server(ftype)

  lsp_servers[ftype].job->job_stop()
  lsp_servers[ftype].job = v:none
  lsp_servers[ftype].running = v:false
  lsp_servers[ftype].requests = {}
  return 0
enddef

# Send a LSP "textDocument/didOpen" notification
def lsp#textdoc_didopen(fname: string, ftype: string): void
  var notif: dict<any> = lsp#create_notifmsg(ftype, 'textDocument/didOpen')

  # interface DidOpenTextDocumentParams
  # interface TextDocumentItem
  var tdi = {}
  tdi.uri = 'file://' .. fname
  tdi.languageId = ftype
  tdi.version = 1
  tdi.text = readfile(fname)->join("\n")
  notif.params->extend({'textDocument': tdi})

  lsp#sendto_server(ftype, notif)
enddef

# Send a LSP "textDocument/didClose" notification
def lsp#textdoc_didclose(fname: string, ftype: string): void
  var notif: dict<any> = lsp#create_notifmsg(ftype, 'textDocument/didClose')

  # interface DidCloseTextDocumentParams
  #   interface TextDocumentIdentifier
  var tdid = {}
  tdid.uri = 'file://' .. fname
  notif.params->extend({'textDocument': tdid})

  lsp#sendto_server(ftype, notif)
enddef

# Goto a definition using "textDocument/definition" LSP request
def lsp#goto_definition(fname: string, ftype: string, lnum: number, col: number)
  if fname == '' || ftype == ''
    return
  endif
  if !lsp_servers->has_key(ftype)
    echomsg 'Error: LSP server for "' .. ftype .. '" filetype is not found'
    return
  endif
  if !lsp_servers[ftype].running
    echomsg 'Error: LSP server for "' .. ftype .. '" filetype is not running'
    return
  endif

  var req = lsp#create_reqmsg(ftype, 'textDocument/definition')

  # interface DefinitionParams
  # interface TextDocumentPositionParams
  # interface TextDocumentIdentifier
  req.params->extend({'textDocument': {'uri': 'file://' .. fname}})
  # interface Position
  req.params->extend({'position': {'line': lnum, 'character': col}})

  lsp#sendto_server(ftype, req)
enddef

# Goto a declaration using "textDocument/declaration" LSP request
def lsp#goto_declaration(fname: string, ftype: string, lnum: number, col: number)
  if fname == '' || ftype == ''
    return
  endif
  if !lsp_servers->has_key(ftype)
    echomsg 'Error: LSP server for "' .. ftype .. '" filetype is not found'
    return
  endif
  if !lsp_servers[ftype].running
    echomsg 'Error: LSP server for "' .. ftype .. '" filetype is not running'
    return
  endif

  var req = lsp#create_reqmsg(ftype, 'textDocument/declaration')

  # interface DeclarationParams
  #   interface TextDocumentPositionParams
  #     interface TextDocumentIdentifier
  req.params->extend({'textDocument': {'uri': 'file://' .. fname}})
  #     interface Position
  req.params->extend({'position': {'line': lnum, 'character': col}})

  lsp#sendto_server(ftype, req)
enddef

# Get the signature using "textDocument/signatureHelp" LSP request
def lsp#show_signature(): string

  # first send all the changes to the current buffer to the LSP server
  listener_flush()

  var fname: string = expand('%:p')
  var ftype: string = &filetype
  var lnum: number = line('.') - 1
  var col: number = col('.') - 1

  if fname == '' || ftype == ''
    return ''
  endif
  if !lsp_servers->has_key(ftype)
    echomsg 'Error: LSP server for "' .. ftype .. '" filetype is not found'
    return ''
  endif
  if !lsp_servers[ftype].running
    echomsg 'Error: LSP server for "' .. ftype .. '" filetype is not running'
    return ''
  endif

  var req = lsp#create_reqmsg(ftype, 'textDocument/signatureHelp')
  # interface SignatureHelpParams
  #   interface TextDocumentPositionParams
  #     interface TextDocumentIdentifier
  req.params->extend({'textDocument': {'uri': 'file://' .. fname}})
  #     interface Position
  req.params->extend({'position': {'line': lnum, 'character': col}})

  lsp#sendto_server(ftype, req)
  return ''
enddef

# buffer change notification listener
def lsp#bufchange_listener(bnum: number, start: number, end: number, added: number, changes: list<dict<number>>)
  var ftype = getbufvar(bnum, '&filetype')
  var notif: dict<any> = lsp#create_notifmsg(ftype, 'textDocument/didChange')

  # interface DidChangeTextDocumentParams
  #   interface VersionedTextDocumentIdentifier
  var vtdid: dict<any> = {}
  vtdid.uri = 'file://' .. fnamemodify(bufname(bnum), ':p')
  # Use Vim 'changedtick' as the LSP document version number
  vtdid.version = getbufvar(bnum, 'changedtick')
  notif.params->extend({'textDocument': vtdid})
  #   interface TextDocumentContentChangeEvent
  var changeset: list<dict<any>> = []
  #     Range
  var range: dict<dict<number>> = {}
  range.start = {'line': start - 1, 'character': 0}
  range.end = {'line': end - 2, 'character': 0}
  changeset->add({'range': range, 'text': getbufline(bnum, start, end - 1)->join("\n")})
  notif.params->extend({'contentChanges': changeset})

  lsp#sendto_server(ftype, notif)
enddef

def lsp#add_file(fname: string, ftype: string): void
  if fname == '' || ftype == '' || !lsp_servers->has_key(ftype)
    return
  endif
  if !lsp_servers[ftype].running
    lsp#start_server(ftype)
  endif
  lsp#textdoc_didopen(fname, ftype)

  # add a listener to track changes to this buffer
  var bnum = bufnr(fname)
  if bnum != -1
    listener_add(function('lsp#bufchange_listener'), bnum)
  endif
enddef

def lsp#remove_file(fname: string, ftype: string): void
  if fname == '' || ftype == '' || !lsp_servers->has_key(ftype)
    return
  endif
  if !lsp_servers[ftype].running
    lsp#start_server(ftype)
  endif
  lsp#textdoc_didclose(fname, ftype)
enddef

def lsp#stop_all_servers()
  for [ftype, server] in items(lsp_servers)
    if server.running
      lsp#stop_server(ftype)
    endif
  endfor
enddef

def lsp#add_server(ftype: string, serverpath: string, args: list<string>)
  var sinfo = {
    'path': serverpath,
    'args': args,
    'running': v:false,
    'job': v:none,
    'data': '',
    'nextID': 1,
    'caps': {},
    'requests': {}    # outstanding LSP requests
  }
  lsp_servers->extend({[ftype]: sinfo})
enddef

def lsp#show_servers()
  echomsg lsp_servers
enddef

# vim: shiftwidth=2 sts=2 expandtab
