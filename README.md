![unit-tests](https://github.com/yegappan/lsp/workflows/unit-tests/badge.svg?branch=main)

Language Server Protocol (LSP) plugin for Vim. You need Vim version 9.0 or above to use this plugin.  This plugin is written using only the Vim9 script.

## Installation

You can install this plugin directly from github using the following steps:

```bash
$ mkdir -p $HOME/.vim/pack/downloads/opt
$ cd $HOME/.vim/pack/downloads/opt
$ git clone https://github.com/yegappan/lsp
```

After installing the plugin using the above steps, add the following line to
your $HOME/.vimrc file:

```viml
packadd lsp
```

You can also install and manage this plugin using any one of the Vim plugin managers (dein.vim, pathogen, vam, vim-plug, volt, Vundle, etc.).

You will also need to download and install one or more language servers corresponding to the programming languages that you are using. Refer to the https://langserver.org/ page for the list of available language servers.  This plugin doesn't install the language servers.

## Features

The following language server protocol (LSP) features are supported:

* Code completion
* Jump to definition, declaration, implementation, type definition
* Display warning and error diagnostics
* Find all symbol references
* Workspace symbol search
* Display code outline
* Rename symbol
* Display type and documentation on hover
* Signature help
* Code action
* Display Call hierarchy
* Display Type hierarchy
* Formatting code
* Folding code
* Visually select symbol block/region

## Configuration

To use the plugin features with a particular file type(s), you need to first register a LSP server for that file type(s).

To register a LSP server, add the following lines to your .vimrc file (use only the LSP servers that you need from the below list).  If you used [vim-plug](https://github.com/junegunn/vim-plug) to install the LSP plugin, the steps are described later in this section.
```viml
function! TypeScriptCustomNotificationHandler(lspserver, reply) abort
	echom printf("TypeScript Version = %s", a:reply.params.version)
endfunction
let lspServers = [
	\     #{
	\	 name: 'clangd',
	\	 filetype: ['c', 'cpp'],
	\	 path: '/usr/local/bin/clangd',
	\	 args: ['--background-index']
	\      },
	\     #{
	\	 name: 'typescriptlang',
	\	 filetype: ['javascript', 'typescript'],
	\	 path: '/usr/local/bin/typescript-language-server',
	\	 args: ['--stdio'],
	\	 customNotificationHandlers: {
	\	   '$/typescriptVersion': function('TypeScriptCustomNotificationHandler')
	\	 }
	\      },
	\     #{
	\	 name: 'bashlang',
	\	 filetype: 'sh',
	\	 path: '/usr/local/bin/bash-language-server',
	\	 args: ['start']
	\      },
	\     #{
	\	 name: 'vimlang',
	\	 filetype: 'vim',
	\	 path: '/usr/local/bin/vim-language-server',
	\	 args: ['--stdio']
	\      },
	\     #{
	\	 name: 'golang',
	\	 filetype: ['go', 'gomod'],
	\	 path: '/usr/local/bin/gopls',
	\	 args: ['serve'],
	\	 syncInit: v:true
	\      },
	\     #{
	\	 name: 'rustlang',
	\	 filetype: ['rust'],
	\	 path: '/usr/local/bin/rust-analyzer',
	\	 args: [],
	\	 syncInit: v:true
	\      },
	\     #{
	\	 name: 'pylang',
	\	 filetype: ['python'],
	\	 path: '/usr/local/bin/pyls',
	\	 args: []
	\      },
	\     #{
	\	 name: 'fortranls',
	\	 filetype: ['fortran'],
	\	 path: '/usr/local/bin/fortls',
	\	 args: ['--nthreads=1', '--use_signature_help', '--hover_signature']
	\      },
	\     #{
	\	 name: 'phplang',
	\	 filetype: ['php'],
	\	 path: '/usr/local/bin/intelephense',
	\	 args: ['--stdio'],
	\	 syncInit: v:true,
	\	 initializationOptions: #{
	\	   licenceKey: 'absolute path to file with key or key itself'
	\	 }
	\      }
	\   ]
call LspAddServer(lspServers)
```

The above lines add the LSP servers for C, C++, Javascript, Typescript, Shell script, Vim script, Go, Rust, Python, Fortran and PHP file types.  In addition to the above listed file types, this plugin also supports other file types.

To add a LSP server, the following information is needed:

Field|Description
-----|-----------
filetype|One or more file types supported by the LSP server.  This can be a String or a List. To specify multiple multiple file types, use a List.
path|complete path to the LSP server executable (without any arguments).
args|a list of command-line arguments passed to the LSP server. Each argument is a separate List item.
initializationOptions|User provided initialization options. May be of any type. For example the *intelephense* PHP language server accept several options here with the License Key among others. 
customNotificationHandlers|A dictionary of notifications and functions that can be specified to add support for custom language server notifications.
features|A dictionary of booleans that can be specified to toggle what things a given LSP is providing (folding, goto definition, etc) This is useful when running multiple servers in one buffer.

The LSP servers are added using the LspAddServer() function. This function accepts a list of LSP servers with the above information.

If you used [vim-plug](https://github.com/junegunn/vim-plug) to install the LSP plugin, then you need to use the VimEnter autocmd to initialize the LSP server and to set the LSP server options.  For example:
```viml
let lspServers = [
	\     #{
	\	 name: 'clang',
	\	 filetype: ['c', 'cpp'],
	\	 path: '/usr/local/bin/clangd',
	\	 args: ['--background-index']
	\      }
	\   ]
autocmd VimEnter * call LspAddServer(lspServers)

let lspOpts = {'autoHighlightDiags': v:true}
autocmd VimEnter * call LspOptionsSet(lspOpts)
```

## Supported Commands

The following commands are provided to use the LSP features.

Command|Description
-------|-----------
:LspCodeAction|Apply the code action supplied by the language server to the diagnostic in the current line.
:LspCodeLens|Display a list of code lens commands and apply a selected code lens command to the current file.
:LspDiagCurrent|Display the diagnostic message for the current line.
:LspDiagFirst|Jump to the first diagnostic message for the current buffer.
:LspDiagHere|Jump to the next diagnostic message in the current line.
:LspDiagHighlightDisable|Disable diagnostic message highlights.
:LspDiagHighlightEnable|Enable diagnostic message highlights.
:LspDiagNext|Jump to the next diagnostic message after the current position.
:LspDiagPrev|Jump to the previous diagnostic message before the current position.
:LspDiagShow|Display the diagnostics messages from the language server for the current buffer in a new location list.
:LspFold|Fold the current file.
:LspFormat|Format a range of lines in the current file using the language server. The **shiftwidth** and **expandtab** values set for the current buffer are used when format is applied.  The default range is the entire file.
:LspGotoDeclaration|Go to the declaration of the keyword under cursor.
:LspGotoDefinition|Go to the definition of the keyword under cursor.
:LspGotoImpl|Go to the implementation of the keyword under cursor.
:LspGotoTypeDef|Go to the type definition of the keyword under cursor.
:LspHighlight|Highlight all the matches for the keyword under cursor.
:LspHighlightClear|Clear all the matches highlighted by :LspHighlight.
:LspHover|Show the documentation for the symbol under the cursor in a popup window.
:LspIncomingCalls|Display the list of symbols calling the current symbol.
:LspOutgoingCalls|Display the list of symbols called by the current symbol.
:LspOutline|Show the list of symbols defined in the current file in a separate window.
:LspPeekDeclaration|Open the declaration of the symbol under cursor in the preview window.
:LspPeekDefinition|Open the definition of the symbol under cursor in the preview window.
:LspPeekImpl|Open the implementation of the symbol under cursor in the preview window.
:LspPeekReferences|Display the list of references to the keyword under cursor in a location list associated with the preview window.
:LspPeekTypeDef|Open the type definition of the symbol under cursor in the preview window.
:LspRename|Rename the current symbol.
:LspSelectionExpand|Expand the current symbol range visual selection.
:LspSelectionShrink|Shrink the current symbol range visual selection.
:LspShowAllServers|Display information about all the registered language servers.
:LspServer|Display the capabilities or messages or status of the language server for the current buffer or restart the server.
:LspShowReferences|Display the list of references to the keyword under cursor in a new location list.
:LspShowSignature|Display the signature of the keyword under cursor.
:LspSubTypeHierarchy|Display the sub type hierarchy in a popup window.
:LspSuperTypeHierarchy|Display the super type hierarchy in a popup window.
:LspSwitchSourceHeader|Switch between a source and a header file.
:LspSymbolSearch|Perform a workspace wide search for a symbol.
:LspWorkspaceAddFolder `{folder}`| Add a folder to the workspace.
:LspWorkspaceListFolders|Show the list of folders in the workspace.
:LspWorkspaceRemoveFolder `{folder}`|Remove a folder from the workspace.

## Similar Vim LSP Plugins

1. [vim-lsp: Async Language Server Protocol](https://github.com/prabirshrestha/vim-lsp)
1. [Coc: Conquer of Completion](https://github.com/neoclide/coc.nvim)
1. [vim-lsc: Vim Language Server Client](https://github.com/natebosch/vim-lsc)
1. [LanguageClient-neovim](https://github.com/autozimu/LanguageClient-neovim)
1. [ALE: Asynchronous Lint Engine](https://github.com/dense-analysis/ale)
1. [Neovim built-in LSP client](https://neovim.io/doc/user/lsp.html)
