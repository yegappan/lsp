vim9script

# Functions for dealing with call hierarchy (incoming/outgoing calls)

import './util.vim'
import './buffer.vim' as buf

# Jump to the location of the symbol under the cursor in the call hierarchy
# tree window.
def CallHierarchyItemJump()
  var item: dict<any> = w:LspCallHierItemMap[line('.')].item
  util.JumpToLspLocation(item, '')
enddef

# Refresh the call hierarchy tree for the symbol at index "idx".
def CallHierarchyTreeItemRefresh(idx: number)
  var treeItem: dict<any> = w:LspCallHierItemMap[idx]

  if treeItem.open
    # Already retrieved the children for this item
    return
  endif

  if !treeItem->has_key('children')
    # First time retrieving the children for the item at index "idx"
    var lspserver = buf.BufLspServerGet(w:LspBufnr, 'callHierarchy')
    if lspserver->empty() || !lspserver.running
      return
    endif

    var reply: any
    if w:LspCallHierIncoming
      reply = lspserver.getIncomingCalls(treeItem.item)
    else
      reply = lspserver.getOutgoingCalls(treeItem.item)
    endif

    treeItem.children = []
    if !reply->empty()
      for item in reply
	treeItem.children->add({item: w:LspCallHierIncoming ? item.from :
				item.to, open: false})
      endfor
    endif
  endif

  # Clear and redisplay the tree in the window
  treeItem.open = true
  var save_cursor = getcurpos()
  CallHierarchyTreeRefresh()
  setpos('.', save_cursor)
enddef

# Open the call hierarchy tree item under the cursor
def CallHierarchyTreeItemOpen()
  CallHierarchyTreeItemRefresh(line('.'))
enddef

# Refresh the entire call hierarchy tree
def CallHierarchyTreeRefreshCmd()
  w:LspCallHierItemMap[2].open = false
  w:LspCallHierItemMap[2]->remove('children')
  CallHierarchyTreeItemRefresh(2)
enddef

# Display the incoming call hierarchy tree
def CallHierarchyTreeIncomingCmd()
  w:LspCallHierItemMap[2].open = false
  w:LspCallHierItemMap[2]->remove('children')
  w:LspCallHierIncoming = true
  CallHierarchyTreeItemRefresh(2)
enddef

# Display the outgoing call hierarchy tree
def CallHierarchyTreeOutgoingCmd()
  w:LspCallHierItemMap[2].open = false
  w:LspCallHierItemMap[2]->remove('children')
  w:LspCallHierIncoming = false
  CallHierarchyTreeItemRefresh(2)
enddef

# Close the call hierarchy tree item under the cursor
def CallHierarchyTreeItemClose()
  var treeItem: dict<any> = w:LspCallHierItemMap[line('.')]
  treeItem.open = false
  var save_cursor = getcurpos()
  CallHierarchyTreeRefresh()
  setpos('.', save_cursor)
enddef

# Recursively add the call hierarchy items to w:LspCallHierItemMap
def CallHierarchyTreeItemShow(incoming: bool, treeItem: dict<any>, pfx: string)
  var item = treeItem.item
  var treePfx: string
  if treeItem.open && treeItem->has_key('children')
    treePfx = has('gui_running') ? '▼' : '-'
  else
    treePfx = has('gui_running') ? '▶' : '+'
  endif
  var fname = util.LspUriToFile(item.uri)
  var s = $'{pfx}{treePfx} {item.name} ({fname->fnamemodify(":t")} [{fname->fnamemodify(":h")}])'
  append('$', s)
  w:LspCallHierItemMap->add(treeItem)
  if treeItem.open && treeItem->has_key('children')
    for child in treeItem.children
      CallHierarchyTreeItemShow(incoming, child, $'{pfx}  ')
    endfor
  endif
enddef

def CallHierarchyTreeRefresh()
  :setlocal modifiable
  :silent! :%d _

  setline(1, $'# {w:LspCallHierIncoming ? "Incoming calls to" : "Outgoing calls from"} "{w:LspCallHierarchyTree.item.name}"')
  w:LspCallHierItemMap = [{}, {}]
  CallHierarchyTreeItemShow(w:LspCallHierIncoming, w:LspCallHierarchyTree, '')
  :setlocal nomodifiable
enddef

def CallHierarchyTreeShow(incoming: bool, prepareItem: dict<any>,
			  items: list<dict<any>>)
  var save_bufnr = bufnr()
  var wid = bufwinid('LSP-CallHierarchy')
  if wid != -1
    wid->win_gotoid()
  else
    :new LSP-CallHierarchy
    :setlocal buftype=nofile
    :setlocal bufhidden=wipe
    :setlocal noswapfile
    :setlocal nonumber nornu
    :setlocal fdc=0 signcolumn=no

    :nnoremap <buffer> <CR> <ScriptCmd>CallHierarchyItemJump()<CR>
    :nnoremap <buffer> - <ScriptCmd>CallHierarchyTreeItemOpen()<CR>
    :nnoremap <buffer> + <ScriptCmd>CallHierarchyTreeItemClose()<CR>
    :command -buffer LspCallHierarchyRefresh CallHierarchyTreeRefreshCmd()
    :command -buffer LspCallHierarchyIncoming CallHierarchyTreeIncomingCmd()
    :command -buffer LspCallHierarchyOutgoing CallHierarchyTreeOutgoingCmd()

    :syntax match Comment '^#.*$'
    :syntax match Directory '(.*)$'
  endif

  w:LspBufnr = save_bufnr
  w:LspCallHierIncoming = incoming
  w:LspCallHierarchyTree = {}
  w:LspCallHierarchyTree.item = prepareItem
  w:LspCallHierarchyTree.open = true
  w:LspCallHierarchyTree.children = []
  for item in items
    w:LspCallHierarchyTree.children->add({item: incoming ? item.from : item.to, open: false})
  endfor

  CallHierarchyTreeRefresh()

  :setlocal nomodified
  :setlocal nomodifiable
enddef

export def IncomingCalls(lspserver: dict<any>)
  var prepareReply = lspserver.prepareCallHierarchy()
  if prepareReply->empty()
    util.WarnMsg('No incoming calls')
    return
  endif

  var reply = lspserver.getIncomingCalls(prepareReply)
  if reply->empty()
    util.WarnMsg('No incoming calls')
    return
  endif

  CallHierarchyTreeShow(true, prepareReply, reply)
enddef

export def OutgoingCalls(lspserver: dict<any>)
  var prepareReply = lspserver.prepareCallHierarchy()
  if prepareReply->empty()
    util.WarnMsg('No outgoing calls')
    return
  endif

  var reply = lspserver.getOutgoingCalls(prepareReply)
  if reply->empty()
    util.WarnMsg('No outgoing calls')
    return
  endif

  CallHierarchyTreeShow(false, prepareReply, reply)
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2
