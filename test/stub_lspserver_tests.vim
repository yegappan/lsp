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

def StubTraceLog(lspserver: dict<any>, msg: string)
enddef

def MakeRequestTestLspServer(responses: list<dict<any>>): dict<any>
  var lspserver = MakeTestLspServer([])
  lspserver.sendResponse = function(CaptureResponse, [responses])
  lspserver.traceLog = function(StubTraceLog, [lspserver])
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

# Only here to because the test runner needs it
def g:StartLangServer(): bool
  return true
enddef

# vim: tabstop=8 shiftwidth=2 softtabstop=2 noexpandtab
