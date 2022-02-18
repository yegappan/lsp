![unit-tests](https://github.com/yegappan/mru/workflows/unit-tests/badge.svg?branch=master)

Language Server Protocol (LSP) plugin for Vim9. You need Vim version 8.2.2342 or above to use this plugin.

## Installation

You can install this plugin directly from github using the following steps:

```
    $ mkdir -p $HOME/.vim/pack/downloads/opt/lsp
    $ cd $HOME/.vim/pack/downloads/opt/lsp
    $ git clone https://github.com/yegappan/lsp
```

After installing the plugin using the above steps, add the following line to
your $HOME/.vimrc file:

```
    packadd lsp
```

You can also install and manage this plugin using any one of the Vim plugin managers (dein.vim, pathogen, vam, vim-plug, volt, Vundle, etc.).

You will also need to install one or more language servers corresponding to the programming languages that you are using. Refer to the https://langserver.org/ page for the list of available language servers.

## Configuration

To register a LSP server, add the following lines to your .vimrc file:
```
   let lspServers = [
		\     {
		\       'filetype': ['c', 'cpp'],
		\       'path': '/usr/local/bin/clangd',
		\       'args': ['--background-index']
		\     },
		\     {
		\	'filetype': ['javascript', 'typescript'],
		\	'path': '/usr/local/bin/typescript-language-server',
		\	'args': ['--stdio']
		\     },
		\     {
		\	'filetype': 'sh',
		\	'path': '/usr/local/bin/bash-language-server',
		\	'args': ['start']
		\     },
		\     {
		\	'filetype': 'vim',
		\	'path': '/usr/local/bin/vim-language-server',
		\	'args': ['--stdio']
		\     },
		\     {
		\	'filetype': ['go', 'gomod'],
		\	'path': '/usr/local/bin/gopls',
		\	'args': []
		\     },
		\     {
		\	'filetype': ['python'],
		\	'path': '/usr/local/bin/pyls',
		\	'args': []
		\     },
		\     {
		\	'filetype': ['fortran'],
		\	'path': '/usr/local/bin/fortls',
		\	'args': ['--nthreads=1', '--use_signature_help', '--hover_signature']
		\     }
		\   ]
   call LspAddServer(lspServers)
```

The above lines add the LSP servers for C, C++, Javascript, Typescript, Shell script, Vim script, Go and Python file types.

To add a LSP server, the following information is needed:

Field|Description
-----|-----------
filetype|One or more file types supported by the LSP server.  This can be a String or a List. To specify multiple multiple file types, use a List.
path|complete path to the LSP server executable (without any arguments).
args|a list of command-line arguments passed to the LSP server. Each argument is a separate List item.

The LSP servers are added using the LspAddServer() function. This function accepts a list of LSP servers with the above information.

## Supported Commands
Command|Description
-------|-----------
:LspShowServers|Display the list of registered LSP servers
:LspGotoDefinition|Go to the definition of the keyword under cursor
:LspGotoDeclaration|Go to the declaration of the keyword under cursor
:LspGotoTypeDef|Go to the type definition of the keyword under cursor
:LspGotoImpl|Go to the implementation of the keyword under cursor
:LspPeekDefinition|Open the definition of the symbol under cursor in the preview window.
:LspPeekDeclaration|Open the declaration of the symbol under cursor in the preview window.
:LspPeekTypeDef|Open the type definition of the symbol under cursor in the preview window.
:LspPeekImpl|Open the implementation of the symbol under cursor in the preview window.
:LspShowSignature|Display the signature of the keyword under cursor
:LspDiagShow|Display the diagnostics messages from the LSP server for the current buffer in a new location list.
:LspDiagFirst|Display the first diagnostic message for the current buffer
:LspDiagNext|Display the next diagnostic message after the current line
:LspDiagPrev|Display the previous diagnostic message before the current line
:LspDiagCurrent|Display the diagnostic message for the current line
:LspShowReferences|Display the list of references to the keyword under cursor in a new location list.
:LspPeekReferences|Display the list of references to the keyword under cursor in a location list associated with the preview window.
:LspHighlight|Highlight all the matches for the keyword under cursor
:LspHighlightClear|Clear all the matches highlighted by :LspHighlight
:LspOutline|Show the list of symbols defined in the current file in a separate window.
:LspFormat|Format the current file using the LSP server.
:{range}LspFormat|Format the specified range of lines.
:LspIncomingCalls|Display the list of symbols calling the current symbol.
:LspOutgoingCalls|Display the list of symbols called by the current symbol.
:LspRename|Rename the current symbol
:LspCodeAction|Apply the code action supplied by the LSP server to the diagnostic in the current line.
:LspSymbolSearch|Perform a workspace wide search for a symbol
:LspSelectionExpand|Expand the current symbol range visual selection
:LspSelectionShrink|Shrink the current symbol range visual selection
:LspFold|Fold the current file
:LspWorkspaceAddFolder `{folder}`| Add a folder to the workspace
:LspWorkspaceRemoveFolder `{folder}`|Remove a folder from the workspace
:LspWorkspaceListFolders|Show the list of folders in the workspace
:LspServerRestart|Restart the LSP server for the current buffer

## Similar Vim LSP Plugins

1. [vim-lsp: Async Language Server Protocol](https://github.com/prabirshrestha/vim-lsp)
1. [Coc: Conquer of Completion](https://github.com/neoclide/coc.nvim)
1. [vim-lsc: Vim Language Server Client](https://github.com/natebosch/vim-lsc)
1. [LanguageClient-neovim](https://github.com/autozimu/LanguageClient-neovim)
1. [ALE: Asynchronous Lint Engine](https://github.com/dense-analysis/ale)
1. [Neovim built-in LSP client](https://neovim.io/doc/user/lsp.html)
