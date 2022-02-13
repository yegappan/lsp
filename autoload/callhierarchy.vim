vim9script

# Functions for dealing with call hierarchy (incoming/outgoing calls)

var util = {}
if has('patch-8.2.4019')
  import './util.vim' as util_import

  util.WarnMsg = util_import.WarnMsg
  util.LspUriToFile = util_import.LspUriToFile
  util.GetLineByteFromPos = util_import.GetLineByteFromPos
else
  import {WarnMsg,
	  LspUriToFile,
	  GetLineByteFromPos} from './util.vim'

  util.WarnMsg = WarnMsg
  util.LspUriToFile = LspUriToFile
  util.GetLineByteFromPos = GetLineByteFromPos
endif

def CreateLoclistWithCalls(calls: list<dict<any>>, incoming: bool)
  var qflist: list<dict<any>> = []

  for item in calls
    var fname: string
    if incoming
      fname = util.LspUriToFile(item.from.uri)
    else
      fname = util.LspUriToFile(item.to.uri)
    endif
    var bnr: number = fname->bufnr()
    if bnr == -1
      bnr = fname->bufadd()
    endif
    if !bnr->bufloaded()
      bnr->bufload()
    endif

    var name: string
    if incoming
      name = item.from.name
    else
      name = item.to.name
    endif

    if incoming
      for r in item.fromRanges
        var text: string =
       			bnr->getbufline(r.start.line + 1)[0]->trim("\t ", 1)
        qflist->add({filename: fname,
          		lnum: r.start.line + 1,
          		col: util.GetLineByteFromPos(bnr, r.start) + 1,
          		text: name .. ': ' .. text})
      endfor
    else
      var pos: dict<any> = item.to.range.start
      var text: string = bnr->getbufline(pos.line + 1)[0]->trim("\t ", 1)
      qflist->add({filename: fname,
       		lnum: item.to.range.start.line + 1,
       		col: util.GetLineByteFromPos(bnr, pos) + 1,
       		text: name .. ': ' .. text})
    endif
  endfor
  var save_winid = win_getid()
  setloclist(0, [], ' ', {title: 'Incoming Calls', items: qflist})
  lopen
  save_winid->win_gotoid()
enddef

export def IncomingCalls(calls: list<dict<any>>)
  if calls->empty()
    util.WarnMsg('No incoming calls')
    return
  endif

  CreateLoclistWithCalls(calls, true)
enddef

export def OutgoingCalls(calls: list<dict<any>>)
  if calls->empty()
    util.WarnMsg('No outgoing calls')
    return
  endif

  CreateLoclistWithCalls(calls, false)
enddef

# vim: shiftwidth=2 softtabstop=2
