vim9script
# Unit tests using a stub language server

import '../autoload/lsp/lspserver.vim' as lserver
import '../autoload/lsp/codeaction.vim' as codeaction
import '../autoload/lsp/signature.vim' as signature
import '../autoload/lsp/completion.vim' as completion
import '../autoload/lsp/buffer.vim' as buf

def CaptureNotification(notifications: list<dict<any>>, method: string,
			params: any = {}): void
  notifications->add({method: method, params: params->deepcopy()})
enddef

def StubDiagHandler(diags: list<dict<any>>): list<dict<any>>
  return diags
enddef

def MakeTestLspServer(notifications: list<dict<any>>): dict<any>
  var lspserver = lserver.NewLspServer({
	name: 'test',
	path: 'test-lsp',
	args: [],
	customNotificationHandlers: {},
	customRequestHandlers: {},
	debug: false,
	features: {},
	forceOffsetEncoding: '',
	initializationOptions: {},
	languageId: '',
	processDiagHandler: StubDiagHandler,
	rootSearch: [],
	runIfSearch: [],
	runUnlessSearch: [],
	syncInit: false,
	traceLevel: 'off',
	workspaceConfig: {}
      })
  lspserver.textDocumentSync = 2
  lspserver.sendNotification = function(CaptureNotification, [notifications])
  return lspserver
enddef

def CaptureResponse(responses: list<dict<any>>, request: dict<any>,
      result: any, error: dict<any>): void
  responses->add({id: request.id, result: result, error: error->deepcopy()})
enddef

def CaptureMessage(messages: list<dict<any>>, msg: dict<any>): void
  messages->add(msg->deepcopy())
enddef

def MakeRequestTestLspServer(responses: list<dict<any>>): dict<any>
  var lspserver = MakeTestLspServer([])
  lspserver.sendResponse = function(CaptureResponse, [responses])
  return lspserver
enddef

def AssertRequestError(lspserver: dict<any>, responses: list<dict<any>>,
          request: dict<any>, code: number)
  responses->filter('0')
  lspserver.processRequest(request)
  assert_equal(1, responses->len())
  assert_equal(request.id, responses[0].id)
  assert_equal(code, responses[0].error.code)
enddef

def g:Test_RequestValidation_InvalidRequest()
  var responses: list<dict<any>> = []
  var lspserver = MakeRequestTestLspServer(responses)

  # -32600 InvalidRequest: object params are required but missing.
  AssertRequestError(lspserver, responses,
    {id: 1, method: 'workspace/applyEdit'}, -32600)
  AssertRequestError(lspserver, responses,
    {id: 2, method: 'workspace/configuration'}, -32600)
  AssertRequestError(lspserver, responses,
    {id: 3, method: 'window/showMessageRequest'}, -32600)

  AssertRequestError(lspserver, responses,
    {id: 4, method: 'client/registerCapability'}, -32600)
  AssertRequestError(lspserver, responses,
    {id: 5, method: 'client/unregisterCapability'}, -32600)
  AssertRequestError(lspserver, responses,
    {id: 6, method: 'window/workDoneProgress/create'}, -32600)
enddef

def g:Test_RequestValidation_InvalidParamsAndMethodNotFound()
  var responses: list<dict<any>> = []
  var lspserver = MakeRequestTestLspServer(responses)

  # -32602 InvalidParams: params type/shape is invalid.
  AssertRequestError(lspserver, responses,
    {id: 10, method: 'workspace/applyEdit', params: []}, -32602)
  AssertRequestError(lspserver, responses,
    {id: 11, method: 'workspace/applyEdit', params: {}}, -32602)
  AssertRequestError(lspserver, responses,
    {id: 12, method: 'workspace/configuration', params: {}}, -32602)
  AssertRequestError(lspserver, responses,
    {id: 13, method: 'workspace/configuration', params: {items: {}}}, -32602)
  AssertRequestError(lspserver, responses,
    {id: 14, method: 'window/showMessageRequest', params: {}}, -32602)
  AssertRequestError(lspserver, responses,
    {id: 15, method: 'window/showMessageRequest', params: {message: 99}}, -32602)
  AssertRequestError(lspserver, responses,
    {id: 16, method: 'window/showMessageRequest', params: {message: 'Pick', actions: {}}}, -32602)
  AssertRequestError(lspserver, responses,
    {id: 17, method: 'window/showMessageRequest', params: {message: 'Pick', actions: [{}]}}, -32602)
  AssertRequestError(lspserver, responses,
    {id: 18, method: 'window/showMessageRequest', params: {message: 'Pick', actions: [{title: 1}]}}, -32602)
  AssertRequestError(lspserver, responses,
    {id: 19, method: 'workspace/workspaceFolders', params: {foo: 1}}, -32602)
  AssertRequestError(lspserver, responses,
    {id: 20, method: 'workspace/diagnostic/refresh', params: {foo: 1}}, -32602)
  AssertRequestError(lspserver, responses,
    {id: 21, method: 'client/registerCapability', params: {}}, -32602)
  AssertRequestError(lspserver, responses,
    {id: 22, method: 'client/registerCapability', params: {registrations: {}}}, -32602)
  AssertRequestError(lspserver, responses,
    {id: 23, method: 'client/unregisterCapability', params: {}}, -32602)
  AssertRequestError(lspserver, responses,
    {id: 24, method: 'client/unregisterCapability', params: {unregisterations: {}}}, -32602)
  AssertRequestError(lspserver, responses,
    {id: 25, method: 'window/workDoneProgress/create', params: {}}, -32602)

  # Unknown method should return MethodNotFound.
  AssertRequestError(lspserver, responses,
    {id: 26, method: 'workspace/notARealMethod', params: {}}, -32601)
enddef

def g:Test_ProcessRequest_CustomHandlerException_ReturnsInternalError()
  var responses: list<dict<any>> = []
  var lspserver = MakeRequestTestLspServer(responses)
  lspserver.customRequestHandlers = {
    'custom/fail': (_, _) => {
      throw 'forced failure'
    }
  }

  AssertRequestError(lspserver, responses,
    {id: 27, method: 'custom/fail', params: {}}, -32603)
enddef

def AssertIgnoredUnknownResponse(lspserver: dict<any>, payload: dict<any>, id: string)
  var traceMsgs: list<string> = []
  lspserver.traceLog = (msg) => traceMsgs->add(msg)
  lspserver.processRequest = (_, _) => assert_report('unexpected request dispatch')
  lspserver.processNotif = (_, _) => assert_report('unexpected notification dispatch')

  var beforeMessages = execute('messages')
  lspserver.data = payload
  lspserver.processMessage()

  assert_equal(1, traceMsgs->len())
  assert_match('Ignored response with unknown id from LSP server:', traceMsgs[0])

  var afterMessages = execute('messages')
  assert_equal(-1, afterMessages->stridx($'Unrecognized id in reponse received from LSP server: {id}'))
  assert_equal(beforeMessages, afterMessages)
enddef

def g:Test_ProcessMessages_IgnoreUnknownResponseId_Result()
  var lspserver = MakeTestLspServer([])
  var unknownId = 'X-unknown-response-id-result'
  AssertIgnoredUnknownResponse(lspserver,
    {
      jsonrpc: '2.0',
      id: unknownId,
      result: {}
    }, unknownId)
enddef

def g:Test_ProcessMessages_IgnoreUnknownResponseId_Error()
  var lspserver = MakeTestLspServer([])
  var unknownId = 'X-unknown-response-id-error'
  AssertIgnoredUnknownResponse(lspserver,
    {
      jsonrpc: '2.0',
      id: unknownId,
      error: {
        code: -32601,
        message: 'Method not found'
      }
    }, unknownId)
enddef

def g:Test_ProcessMessages_RejectsMessageMissingJsonRpc()
  var lspserver = MakeTestLspServer([])
  var traceMsgs: list<string> = []
  lspserver.traceLog = (msg) => traceMsgs->add(msg)
  lspserver.processRequest = (_, _) => assert_report('unexpected request dispatch')
  lspserver.processNotif = (_, _) => assert_report('unexpected notification dispatch')

  # Message without jsonrpc field should be dropped
  lspserver.data = {
    id: 1,
    method: 'test/method'
  }
  lspserver.processMessage()

  assert_equal(1, traceMsgs->len())
  assert_match('Dropping message missing jsonrpc field:', traceMsgs[0])
enddef

def g:Test_ProcessMessages_RejectsMessageWithInvalidJsonRpcVersion()
  var lspserver = MakeTestLspServer([])
  var traceMsgs: list<string> = []
  lspserver.traceLog = (msg) => traceMsgs->add(msg)
  lspserver.processRequest = (_, _) => assert_report('unexpected request dispatch')
  lspserver.processNotif = (_, _) => assert_report('unexpected notification dispatch')

  # Message with wrong jsonrpc version should be dropped
  lspserver.data = {
    jsonrpc: '1.0',
    id: 1,
    method: 'test/method'
  }
  lspserver.processMessage()

  assert_equal(1, traceMsgs->len())
  assert_match('Dropping message with invalid jsonrpc version: 1.0', traceMsgs[0])
enddef

def g:Test_ProcessMessages_AcceptsValidJsonRpcVersion()
  var lspserver = MakeTestLspServer([])
  var traceMsgs: list<string> = []
  var requestsProcessed: number = 0
  lspserver.traceLog = (msg) => traceMsgs->add(msg)
  lspserver.processRequest = (_) => {
    requestsProcessed += 1
  }
  lspserver.processNotif = (_, _) => assert_report('unexpected notification dispatch')

  # Message with correct jsonrpc version should be processed
  lspserver.data = {
    jsonrpc: '2.0',
    id: 1,
    method: 'test/method'
  }
  lspserver.processMessage()

  assert_equal(1, requestsProcessed)
  assert_equal(0, traceMsgs->len())
enddef

def g:Test_PullDiagnostics_RetriggersServerCancelledRequest()
  silent! edit XPullDiagnosticsRetrigger.rs
  setline(1, ['fn main() {}'])

  var queued: list<number> = []
  var rpcOpts: list<dict<any>> = []
  def MockDiagnosticRpc(_method: string, _params: any,
                        opts: dict<any> = {}): dict<any>
    rpcOpts->add(opts->deepcopy())
    return {
      error: {
        code: -32802,
        message: 'server cancelled the request',
        data: {
          retriggerRequest: true
        }
      }
    }
  enddef

  var lspserver = MakeTestLspServer([])
  lspserver.running = true
  lspserver.ready = true
  lspserver.isDiagnosticsProvider = true
  lspserver.features = {diagnostics: true}
  lspserver.featureEnabled = (_) => true
  lspserver.queuePullDiagnostics = (bnr: number) => queued->add(bnr)
  lspserver.rpc = MockDiagnosticRpc

  buf.BufLspServerSet(bufnr(), lspserver)
  lspserver.pullDiagnostics(bufnr())

  assert_equal([{handleError: false}], rpcOpts)
  assert_equal([bufnr()], queued)

  buf.BufLspServerRemove(bufnr(), lspserver)
  :%bw!
enddef

def g:Test_ProcessMessages_InvalidRequest_NonStringMethod_WithId()
  var lspserver = MakeTestLspServer([])
  var outMessages: list<dict<any>> = []
  var traceMsgs: list<string> = []
  lspserver.sendMessage = (msg) => CaptureMessage(outMessages, msg)
  lspserver.traceLog = (msg) => traceMsgs->add(msg)
  lspserver.processRequest = (_, _) => assert_report('unexpected request dispatch')
  lspserver.processNotif = (_, _) => assert_report('unexpected notification dispatch')

  lspserver.data = {
    jsonrpc: '2.0',
    id: 99,
    method: 1
  }
  lspserver.processMessage()

  assert_equal(1, outMessages->len())
  assert_equal('2.0', outMessages[0].jsonrpc)
  assert_equal(99, outMessages[0].id)
  assert_equal(-32600, outMessages[0].error.code)
  assert_equal('Invalid request', outMessages[0].error.message)
  assert_match('Dropping malformed message with non-string method:', traceMsgs[0])
enddef

def g:Test_ProcessMessages_InvalidRequest_InvalidIdType_RespondsWithNullId()
  var lspserver = MakeTestLspServer([])
  var outMessages: list<dict<any>> = []
  var traceMsgs: list<string> = []
  lspserver.sendMessage = (msg) => CaptureMessage(outMessages, msg)
  lspserver.traceLog = (msg) => traceMsgs->add(msg)
  lspserver.processRequest = (_, _) => assert_report('unexpected request dispatch')
  lspserver.processNotif = (_, _) => assert_report('unexpected notification dispatch')

  lspserver.data = {
    jsonrpc: '2.0',
    id: {},
    method: 'workspace/configuration'
  }
  lspserver.processMessage()

  assert_equal(1, outMessages->len())
  assert_equal(null, outMessages[0].id)
  assert_equal(-32600, outMessages[0].error.code)
  assert_match('Dropping malformed request with invalid id type:', traceMsgs[0])
enddef

def g:Test_ProcessMessages_InvalidRequest_MissingMethod_WithId()
  var lspserver = MakeTestLspServer([])
  var outMessages: list<dict<any>> = []
  var traceMsgs: list<string> = []
  lspserver.sendMessage = (msg) => CaptureMessage(outMessages, msg)
  lspserver.traceLog = (msg) => traceMsgs->add(msg)
  lspserver.processRequest = (_, _) => assert_report('unexpected request dispatch')
  lspserver.processNotif = (_, _) => assert_report('unexpected notification dispatch')

  lspserver.data = {
    jsonrpc: '2.0',
    id: 'abc'
  }
  lspserver.processMessage()

  assert_equal(1, outMessages->len())
  assert_equal('abc', outMessages[0].id)
  assert_equal(-32600, outMessages[0].error.code)
  assert_match('Dropping malformed message missing method:', traceMsgs[0])
enddef

def g:Test_ProcessMessages_MalformedNotification_NoResponseSent()
  var lspserver = MakeTestLspServer([])
  var outMessages: list<dict<any>> = []
  var traceMsgs: list<string> = []
  lspserver.sendMessage = (msg) => CaptureMessage(outMessages, msg)
  lspserver.traceLog = (msg) => traceMsgs->add(msg)
  lspserver.processRequest = (_, _) => assert_report('unexpected request dispatch')
  lspserver.processNotif = (_, _) => assert_report('unexpected notification dispatch')

  lspserver.data = {
    jsonrpc: '2.0',
    method: {}
  }
  lspserver.processMessage()

  assert_equal(0, outMessages->len())
  assert_match('Dropping malformed message with non-string method:', traceMsgs[0])
enddef

def g:Test_ProcessMessages_MalformedResponse_BothResultAndError_Dropped()
  var lspserver = MakeTestLspServer([])
  var traceMsgs: list<string> = []
  lspserver.traceLog = (msg) => traceMsgs->add(msg)
  lspserver.processRequest = (_, _) => assert_report('unexpected request dispatch')
  lspserver.processNotif = (_, _) => assert_report('unexpected notification dispatch')

  lspserver.data = {
    jsonrpc: '2.0',
    id: 1,
    result: {},
    error: {code: -32603, message: 'Internal error'}
  }
  lspserver.processMessage()

  assert_equal(1, traceMsgs->len())
  assert_match('Dropping malformed response message:', traceMsgs[0])
enddef

def g:Test_ProcessApplyEditReq_SuccesssfulEdit()
  var lspserver = MakeTestLspServer([])
  var responses: list<dict<any>> = []
  lspserver.sendResponse = (request, result, error) => CaptureResponse(responses, request, result, error)

  lspserver.data = {
    jsonrpc: '2.0',
    id: 1,
    method: 'workspace/applyEdit',
    params: {
      edit: {}
    }
  }
  lspserver.processMessage()

  assert_equal(1, responses->len())
  assert_equal({applied: true}, responses[0].result)
  assert_equal(1, responses[0].error->empty())
enddef

def g:Test_ProcessApplyEditReq_MissingEdit()
  var lspserver = MakeTestLspServer([])
  var responses: list<dict<any>> = []
  lspserver.sendResponse = (request, result, error) => CaptureResponse(responses, request, result, error)

  var request = {
    jsonrpc: '2.0',
    id: 1,
    method: 'workspace/applyEdit',
    params: {}
  }

  AssertRequestError(lspserver, responses, request, -32602)
enddef

def g:Test_ProcessShowMessageRequest_EmptyActions()
  var lspserver = MakeTestLspServer([])
  var responses: list<dict<any>> = []
  lspserver.sendResponse = (request, result, error) => CaptureResponse(responses, request, result, error)

  var request = {
    jsonrpc: '2.0',
    id: 1,
    method: 'window/showMessageRequest',
    params: {
      message: 'Test message',
      actions: []
    }
  }

  AssertRequestError(lspserver, responses, request, -32602)
enddef

def g:Test_ProcessShowMessageRequest_ValidMessage()
  var lspserver = MakeTestLspServer([])
  var responses: list<dict<any>> = []
  lspserver.sendResponse = (request, result, error) => CaptureResponse(responses, request, result, error)

  lspserver.data = {
    jsonrpc: '2.0',
    id: 1,
    method: 'window/showMessageRequest',
    params: {
      message: 'Test message'
    }
  }
  lspserver.processMessage()

  assert_equal(1, responses->len())
  assert_equal(null, responses[0].result)
  assert_equal(1, responses[0].error->empty())
enddef

# Only here to because the test runner needs it
def g:StartLangServer(): bool
  return true
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
