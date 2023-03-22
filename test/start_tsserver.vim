vim9script
source common.vim
g:LoadLspPlugin()
var lspServers = [{
filetype: ['typescript', 'javascript'],
	  path: exepath('typescript-language-server'),
	  args: ['--stdio']
}]
g:LspAddServer(lspServers)
g:StartLangServerWithFile('Xtest.ts')
