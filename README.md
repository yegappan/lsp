# LSP vim9 plugin

Language Server Protocol (LSP) plugin for Vim9.

# Installation

You can install this plugin directly from github using the following steps:

```
    $ mkdir -p $HOME/.vim/pack/downloads/lsp
    $ cd $HOME/.vim/packa/downloads/lsp
    $ git clone https://github.com/yegappan/lsp
```

or you can use any one of the Vim plugin managers (dein.vim, pathogen, vam,
vim-plug, volt, Vundle, etc.) to install and manage this plugin.

You will also need to install one or more language servers corresponding to the
programming languages that you are using. Refer to the https://langserver.org/
page for the list of available language servers.

# Configuration

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
		\     }
		\     {
		\	'filetype': 'sh',
		\	'path': '/usr/local/bin/bash-language-server',
		\	'args': ['start']
		\     },
		\   ]
   call lsp#addServer(lspServers)
```

The above lines add the LSP servers for C, C++, Javascript, Typescript and
Shell script file types.

To add a LSP server, the following information is needed:

Field|Description
-----|-----------
filetype|One or more file types supported by the LSP server.  This can be a String or a List. To specify multiple multiple file types, use a List.
path|complete path to the LSP server executable (without any arguments).
args|a list of command-line arguments passed to the LSP server. Each argument is a separate List item.

The LSP servers are added using the lsp#addServer() function. This function
accepts a list of LSP servers with the above information.
