# Language Server Specific Configuration

Information about using various language servers with the LSP plugin is below.
A sample VimScript code snippet is given for each language server to register the server with the LSP plugin.
A sample absolute path to the language server executable is used in these examples.
You may need to modify the path to match where the language server is installed in your system.
In some cases, it may be simpler to add the language server path to the PATH environment variable.

If your preferred LSP is not found, then possibly it is listed at [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.md) where its `Default config` section can be transferred by setting

- `filetype:` here to the array of values of `Filetypes` there,
- `path` here to the first entry of `cmd`, and
- `args` here to the subsequent entries of `cmd`.

Additional entries include 

- `rootSearch` here to the array of values `root_markers` there where each directory path needs to end with a slash, and
- `settings` *there* to `initializationOptions.settings` here.

## Overview
[Angular Language Server](#angular-language-server)<br>
[AWK Language Server](#awk-language-server)<br>
[Bash Language Server](#bash-language-server)<br>
[Bitbake Language Server](#bitbake-language-server)<br>
[CSpell LSP](#cspell-lsp)<br>
[Clangd](#clangd)<br>
[CSS Language Server](#css-language-server)<br>
[Dart](#dart)<br>
[Deno](#deno)<br>
[Eclipse Java Language Server](#eclipse-java-language-server)<br>
[EFM Language Server](#efm-language-server)<br>
[Emmet Language Server](#emmet-language-server)<br>
[Fortran Language Server](#fortran-language-server)<br>
[Gopls](#gopls)<br>
[HTML Language Server](#html-language-server)<br>
[Jedi Language Server](#jedi-language-server)<br>
[JETLS.jl](#jetls)<br>
[Language Server Bitbake](#language-server-bitbake)<br>
[Lua Language Server](#lua-language-server)<br>
[Omnisharp Language Server](#omnisharp-language-server)<br>
[Perl Navigator](#perl-navigator)<br>
[PHP Intelephense](#php-intelephense)<br>
[PKL Language Server](#pkl-language-server)<br>
[Pylsp](#pylsp)<br>
[Pyright](#pyright)<br>
[Rust-analyzer](#rust-analyzer)<br>
[Ruff Server](#ruff-server)<br>
[Solargraph](#solargraph)<br>
[Swift Language Server](#swift-language-server)<br>
[Typescript/Javascript Language Server](#typescript-language-server)<br>
[Vala Language Server](#vala-language-server)<br>
[Verible](#verible)<br>
[VHDL Language Server](#vhdl-language-server)<br>
[Vimscript](#vim-language-server)<br>
[Volar Server](#volar-server)<br>
[VSCode CSS Language Server](#vscode-css-lsp)<br>
[VSCode ESLint Language Server](#vscode-eslint-lsp)<br>
[VSCode HTML Language Server](#vscode-html-lsp)<br>
[VSCode JSON Language Server](#vscode-json-lsp)<br>
[VSCode Markdown Language Server](#vscode-markdown-lsp)<br>
[YAML Language Server](#yaml-language-server)<br>

<a name="angular-language-server"/></a>
## Angular Language Server 
**Language**: [Angular Templates](https://en.wikipedia.org/wiki/Angular_(web_framework))

**Home Page**: [https://github.com/angular/vscode-ng-language-service](https://github.com/angular/vscode-ng-language-service)

Sample code to add the angular language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'angular',
                 \   filetype: 'html',
                 \   path: '/usr/local/bin/ngserver.cmd',
                 \   args: ['--stdio', '--ngProbeLocations', '/usr/local/bin/@angular/language-service', '--tsProbeLocations', '/usr/local/bin/typescript']
                 \ }])
```

Command to install the angular language server on Linux:
```sh
npm install -g @angular/language-server @angular/language-service typescript
```

<a name="awk-language-server"/></a>
## AWK Language Server
**Language**: [AWK scripts](https://en.wikipedia.org/wiki/AWK)

**Home Page**: [https://github.com/Beaglefoot/awk-language-server](https://github.com/Beaglefoot/awk-language-server)

Sample code to add the awk language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'awkls',
                 \   filetype: 'awk',
                 \   path: '/usr/local/bin/awk-language-server',
                 \   args: []
                 \ }])
```

Command to install the awk language server on Linux:
```sh
npm install -g awk-language-server
```

<a name="bash-language-server"/></a>
## Bash Language Server
**Language**: [Bash shell scripts](https://en.wikipedia.org/wiki/Bash_(Unix_shell))

**Home Page**: [https://github.com/bash-lsp/bash-language-server](https://github.com/bash-lsp/bash-language-server)

Sample code to add the bash language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'bashls',
                 \   filetype: 'sh',
                 \   path: '/usr/local/bin/bash-language-server',
                 \   args: ['start']
                 \ }])
```

<a name="bitbake-language-server"/></a>
## Bitbake Language Server
**Language**: [Bitbake scripts](https://en.wikipedia.org/wiki/BitBake)

**Home Page**: [https://github.com/Freed-Wu/bitbake-language-server](https://github.com/Freed-Wu/bitbake-language-server)

Sample code to add the language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'bitbake-language-server',
                 \   filetype: 'bitbake',
                 \   path: 'bitbake-language-server'
                 \ }])
```

The language server provides linting for Bitbake files.

_Note_: This is an unofficial language server.

<a name="cspell-lsp"/></a>
## CSpell LSP
**Home Page**: [https://github.com/vlabo/cspell-lsp](https://github.com/vlabo/cspell-lsp)

Sample code to add the language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'cspell-lsp',
                 \   filetype: [
                 \     'c',
                 \     'cpp',
                 \     'json',
                 \     'vim',
                 \     'gitcommit',
                 \     'markdown',
                 \   ],
                 \   path: 'cspell-lsp',
                 \   args: ['--stdio',
                 \          '--sortWords',
                 \          '--config', '/path/to/cSpell.json',
                 \   ]
                 \ }])
```

_Installation_: 
```sh
npm install -g @vlabo/cspell-lsp
```

<a name="clangd"/></a>
## Clangd
**Language**: C/C++

**Home Page**: [https://clangd.llvm.org/](https://clangd.llvm.org/)

Sample code to add the clangd language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'clangd',
                 \   filetype: ['c', 'cpp'],
                 \   path: '/usr/local/bin/clangd',
                 \   args: ['--background-index', '--clang-tidy']
                 \ }])
```
Optionally add an [autocommand](https://gist.github.com/Konfekt/2d951b9e07831878b1476133c5f37b52) to automatically trigger generation of a compile commands database for navigating the code base.

<a name="css-language-server"/></a>
## CSS Language Server
**Language**: CSS

**Home Page**: [https://github.com/vscode-langservers/vscode-css-languageserver-bin](https://github.com/vscode-langservers/vscode-css-languageserver-bin)

Sample code to add the CSS language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'cssls',
                 \   filetype: 'css',
                 \   path: '/usr/local/node_modules/.bin/css-languageserver',
                 \   args: ['--stdio'],
                 \ }])
```

_Note_: The CSS language server supports code completion only if the _snippetSupport_ option is enabled.

<a name="dart"/></a>
## Dart

**Language**: Dart

**Home Page**: [https://github.com/dart-lang/sdk/blob/main/pkg/analysis_server/tool/lsp_spec/README.md](https://github.com/dart-lang/sdk/blob/main/pkg/analysis_server/tool/lsp_spec/README.md)

Sample code to add the dart language server to the LSP plugin:

```vim
call LspAddServer([#{name: 'dart',
                 \   filetype: ['dart'],
                 \   path: '/usr/lib/dart/bin/dart',
                 \   args: ['language-server', '--client-id', 'vim']
                 \ }])
```

<a name="deno"/></a>
## Deno
**Language**: Typescript/Javascript

**Home Page**: [https://deno.land](https://deno.land)

Sample code to add the deno language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'deno',
                 \   filetype: ['javascript', 'typescript'],
                 \   path: '/usr/local/bin/deno',
                 \   args: ['lsp'],
                 \   debug: v:true,
                 \   initializationOptions: #{
                 \        enable: v:true,
                 \        lint: v:true
                 \   }
                 \ }])
```

<a name="eclipse-java-language-server"/></a>
## Eclipse Java Language Server
**Language**: Java

**Home Page**: [https://github.com/eclipse/eclipse.jdt.ls](https://github.com/eclipse/eclipse.jdt.ls)

Sample code to add the Eclipse Java Development Tools (JDT) language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'jdtls',
                 \   filetype: 'java',
                 \   path: '/usr/local/jdtls/bin/jdtls',
                 \   args: [],
                 \   initializationOptions: #{
                 \       settings: #{
                 \           java: #{
                 \               completion: #{
                 \                   filteredTypes: ["com.sun.*", "java.awt.*", "jdk.*", "org.graalvm.*", "sun.*", "javax.awt.*", "javax.swing.*"],
                 \               },
                 \           },
                 \       },
                 \   },
                 \ }])
```

The [Eclipse Java language server wiki page](https://github.com/eclipse/eclipse.jdt.ls/wiki/Running-the-JAVA-LS-server-from-the-command-line#initialize-request) has more information about the jdtls language server initialization options.  In the above example, the `filteredTypes` item is not mandatory to use the JDT language server with the LSP plugin.  It is included here only as an example.

<a name="efm-language-server"/></a>
## EFM Language Server
**Language**: General Purpose Language Server

**Home Page**: [https://github.com/mattn/efm-langserver](https://github.com/mattn/efm-langserver)

Sample code to add the efm language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'efm-langserver',
		 \   filetype: ['javascript', 'typescript'],
                 \   path: '/usr/local/bin/efm-langserver',
                 \   args: [],
		 \   initializationOptions: #{
		 \       documentFormatting: v:true
		 \   },
		 \   workspaceConfig: #{
		 \     languages: #{
		 \       javascript: [
		 \         #{
		 \            lintCommand: "eslint -f unix --stdin --stdin-filename ${INPUT}",
		 \            lintStdin: v:true,
		 \            lintFormats: ["%f:%l:%c: %m"],
		 \            formatCommand: "eslint --fix-to-stdout --stdin --stdin-filename=${INPUT}",
		 \            formatStdin: v:true
		 \         }
		 \       ],
		 \       typescript: [
		 \         #{
		 \            lintCommand: "eslint -f unix --stdin --stdin-filename ${INPUT}",
		 \            lintStdin: v:true,
		 \            lintFormats: ["%f:%l:%c: %m"],
		 \            formatCommand: "eslint --fix-to-stdout --stdin --stdin-filename=${INPUT}",
		 \            formatStdin: v:true
		 \          }
		 \       ]
		 \     }
		 \   }
                 \ }])
```

<a name="emmet-language-server"/></a>
## Emmet Language Server
**Language**: HTML

**Home Page**: [https://github.com/olrtg/emmet-language-server](https://github.com/olrtg/emmet-language-server)

Sample code to add the emmet language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'emmet',
                 \   filetype: 'html',
                 \   path: '/usr/local/node_modules/.bin/emmet-language-server',
                 \   args: ['--stdio'],
                 \ }])
```

Command to install the emmet language server on Linux:
```sh
npm install -g @olrtg/emmet-language-server
```

<a name="fortran-language-server"/></a>
## Fortran Language Server
**Language**: Fortran

**Home Page**: [https://github.com/hansec/fortran-language-server](https://github.com/hansec/fortran-language-server)

Sample code to add the fortran language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'fortls',
                 \   filetype: 'fortran',
                 \   path: '/usr/local/bin/fortls',
                 \   args: ['--use_signature_help', '--hover_signature']
                 \ }])
```

<a name="gopls"/></a>
## Gopls
**Language**: Go

**Home Page**: [https://github.com/golang/tools/tree/master/gopls](https://github.com/golang/tools/tree/master/gopls)

Sample code to add the gopls language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'gopls',
                 \   filetype: 'go',
                 \   path: '/usr/local/bin/gopls',
                 \   args: ['serve']
                 \ }])
```

**Server Configuration**: [https://github.com/golang/tools/blob/master/gopls/doc/settings.md](https://github.com/golang/tools/blob/master/gopls/doc/settings.md)

To enable the inlay hint support, include the following in the above code to add the gopls language server:
```vim
    \   workspaceConfig: #{
    \     gopls: #{
    \       hints: #{
    \         assignVariableTypes: v:true,
    \         compositeLiteralFields: v:true,
    \         compositeLiteralTypes: v:true,
    \         constantValues: v:true,
    \         functionTypeParameters: v:true,
    \         parameterNames: v:true,
    \         rangeVariableTypes: v:true
    \       }
    \     }
    \   }
```

<a name="html-language-server"/></a>
## HTML Language Server
**Language**: html

**Home Page**: [https://github.com/vscode-langservers/vscode-html-languageserver-bin](https://github.com/vscode-langservers/vscode-html-languageserver-bin)

Sample code to add the HTML language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'htmlls',
                 \   filetype: 'html',
                 \   path: '/usr/local/node_modules/.bin/html-languageserver',
                 \   args: ['--stdio'],
                 \ }])
```

_Note_: The HTML language server supports code completion only if the _snippetSupport_ option is enabled.

<a name="jedi-language-server"/></a>
## Jedi Language Server
**Language**: Python

**Home Page**: [https://github.com/pappasam/jedi-language-server](https://github.com/pappasam/jedi-language-server)

Sample code to add the Jedi language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'jedi',
                 \   filetype: 'python',
                 \   path: '/usr/local/bin/jedi-language-server',
                 \   args: []
                 \ }])
```

<a name="jetls"/></a>
## JETLS.jl
**Language**: [Julia](https://julialang.org/)

**Home Page**: [https://github.com/aviatesk/JETLS.jl](https://github.com/aviatesk/JETLS.jl)

Sample code to add the language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'JETLS.jl',
                 \   filetype: 'julia',
                 \   path: 'jetls',
                 \   args: [
                 \       '--threads=auto',
                 \       '--'
                 \   ]
                 \ }])
```

_Installation_: Clone the [repository](https://github.com/aviatesk/JETLS.jl)
and run 

```sh
julia -e 'using Pkg; Pkg.Apps.add(; url="https://github.com/aviatesk/JETLS.jl", rev="release")'
```
inside it. Add `~/.julia/bin` to `PATH` or set `/home/user/.julia/bin/jetls` as path in the config.

_Note_: The language server is in an early state and currently needs ~30
seconds to start.

<a name="language-server-bitbake"/></a>
## Language Server Bitbake 
**Language**: [Bitbake scripts](https://en.wikipedia.org/wiki/BitBake)

**Home Page**: [https://www.npmjs.com/package/language-server-bitbake](https://www.npmjs.com/package/language-server-bitbake)

Sample code to add the language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'language-server-bitbake',
                 \   filetype: 'bitbake',
                 \   path: 'language-server-bitbake',
                 \   args: ['--stdio']
                 \ }])
```

The official Bitbake language server.

_Note_: The server starts up and works, but seems to send some unsupported
messages to the client.

<a name="lua-language-server"/></a>
## Lua Language Server
**Language**: Lua

**Home Page**: [https://github.com/LuaLS/lua-language-server](https://github.com/LuaLS/lua-language-server)

Sample code to add the luals language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'luals',
                 \   filetype: 'lua',
                 \   path: '/usr/local/luals/bin/lua-language-server',
                 \   args: [],
                 \ }])
```
**Server Configuration**: [https://github.com/LuaLS/lua-language-server/wiki/Settings](https://github.com/LuaLS/lua-language-server/wiki/Settings)

To enable the inlay hint support, include the following in the above code to add the Lua language server:
```vim
    \   workspaceConfig: #{
    \     Lua: #{
    \       hint: #{
    \         enable: v:true,
    \       }
    \     }
    \   }
```

<a name="omnisharp-language-server"/></a>
## Omnisharp Language Server
**Language**: C#

**Home Page**: [https://github.com/OmniSharp/omnisharp-roslyn](https://github.com/OmniSharp/omnisharp-roslyn)

Sample code to add the omnisharp language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'omnisharp',
                 \   filetype: 'cs',
                 \   path: expand('$HOME/omnisharp/omnisharp.exe'),
                 \   args: ['-z', '--languageserver', '--encoding', 'utf-8'],
                 \ }])
```

<a name="perl-navigator"/></a>
## Perl Navigator
**Language**: Perl

**Home Page**: [https://github.com/bscan/PerlNavigator](https://github.com/bscan/PerlNavigator)

Sample code to add the Perl Navigator language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'perlnavigator',
                 \   filetype: ['perl'],
                 \   path: '/usr/bin/node',
                 \   args: ['/usr/local/PerlNavigator/server/out/server.js', '--stdio']
                 \ }])
```

<a name="php-intelephense"/></a>
## PHP Intelephense
**Language**: PHP

**Home Page**: [https://github.com/bmewburn/vscode-intelephense](https://github.com/bmewburn/vscode-intelephense)

Sample code to add the intelephense language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'intelephense',
                 \   filetype: ['php'],
                 \   path: '/usr/local/bin/intelephense',
                 \   args: ['--stdio']
                 \ }])
```

<a name="pkl-language-server"/></a>
## PKL Language Server
**Language**: PKL [https://pkl-lang.org/](https://pkl-lang.org/)

**Home Page**: [https://github.com/apple/pkl-lsp](https://github.com/apple/pkl-lsp)

Sample code to add the language server to the LSP plugin:
```vim
call LspAddServer([#{
                 \   name: 'pkl-lsp',
                 \   filetype: ['pkl'],
                 \   path: 'java',
                 \   args: [
                 \     '-jar',
                 \     '/path/to/pkl-lsp.jar',
                 \   ],
                 \   initializationOptions: #{
                 \     pkl_cli_path: '/usr/bin/pkl'
                 \   },
                 \   syncInit: v:true,
                 \   debug: v:false
                 \ }])
```

_Note_: The path to the `pkl-lsp.jar` and the 
[PKL command-line client](https://pkl-lang.org/main/current/pkl-cli/index.html#installation)
need to be provided.

Requires a recent Java JVM to be installed. Future pkl-lsp version are planned to ship as native binaries.

<a name="pylsp"/></a>
## Pylsp
**Language**: Python

**Home Page**: [https://github.com/python-lsp/python-lsp-server](https://github.com/python-lsp/python-lsp-server)

Sample code to add the pylsp language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'pylsp',
                 \   filetype: 'python',
                 \   path: '/usr/local/bin/pylsp',
                 \   args: []
                 \ }])
```

<a name="pyright"/></a>
## Pyright
**Language**: Python

**Home Page**: [https://github.com/microsoft/pyright](https://github.com/microsoft/pyright)

Sample code to add the pyright language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'pyright',
                 \   filetype: 'python',
                 \   path: '/usr/local/node_modules/.bin/pyright-langserver',
                 \   args: ['--stdio'],
                 \   workspaceConfig: #{
                 \     python: #{
                 \       pythonPath: '/usr/bin/python3.10'
                 \   }}
                 \ }])
```

Command to install the pyright language server on Linux:
```sh
npm install -g pyright
```

**Server Configuration**: [https://microsoft.github.io/pyright/#/configuration](https://microsoft.github.io/pyright/#/configuration)

<a name="ruff-server"/></a>
## Ruff Server
**Language**: Python

**Home Page**: [https://github.com/astral-sh/ruff](https://github.com/astral-sh/ruff)

Sample code to add the Ruff language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'ruff',
                 \   filetype: 'python',
                 \   path: '/usr/local/bin/ruff',
                 \   args: ['server'],
                 \ }])
```
_Note_: A stable language server has been included with Ruff since v0.5.3, `ruff-lsp` is deprecated.

<a name="rust-analyzer"/></a>
## Rust-analyzer
**Language**: Rust

**Home Page**: [https://rust-analyzer.github.io/](https://rust-analyzer.github.io/)

Sample code to add the rust-analyzer language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'rustanalyzer',
                 \   filetype: ['rust'],
                 \   path: '/usr/local/bin/rust-analyzer-x86_64-unknown-linux-gnu',
                 \   args: [],
                 \   syncInit: v:true
                 \ }])
```

**Server Configuration**: [https://rust-analyzer.github.io/manual.html#configuration](https://rust-analyzer.github.io/manual.html#configuration)

To enable the inlay hint support, include the following in the above code to add the rust-analyzer language server:
```vim
    \  initializationOptions: #{
    \    inlayHints: #{
    \      typeHints: #{
    \        enable: v:true
    \      },
    \      parameterHints: #{
    \        enable: v:true
    \      }
    \    },
    \  }
```

<a name="solargraph"/></a>
## Solargraph
**Language**: Ruby

**Home Page**: [https://solargraph.org/](https://solargraph.org/)

Sample code to add the Solargraph language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'solargraph',
                 \   filetype: ['ruby'],
                 \   path: 'solargraph',
                 \   args: ['stdio'],
                 \   initializationOptions: #{ formatting: v:true }
                 \ }])
```

_Note_: Solargraph does not support range formatting, but the current file can be formatted using `:LspFormat`

<a name="swift-language-server"/></a>
## Swift Language Server
**Language**: [Swift](https://www.swift.org/)

**Home Page**: [https://github.com/apple/sourcekit-lsp](https://github.com/apple/sourcekit-lsp)

Sample code to add the swift language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'swiftls',
                 \   filetype: ['swift'],
                 \   path: '/usr/bin/xcrun',
                 \   args: ['sourcekit-lsp']
                 \ }])
```

<a name="typescript-language-server"/></a>
## Typescript/Javascript Language Server
**Language**: Typescript/JavaScript

**Home Page**: [https://github.com/typescript-language-server/typescript-language-server](https://github.com/typescript-language-server/typescript-language-server)

Sample code to add the typescript/javascript language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'tsserver',
                 \   filetype: ['javascript', 'typescript'],
                 \   path: '/usr/local/bin/typescript-language-server',
                 \   args: ['--stdio']
                 \ }])
```

<a name="vala-language-server"/></a>
## Vala Language Server
**Language**: Vala

**Home Page**: [https://github.com/vala-lang/vala-language-server](https://github.com/vala-lang/vala-language-server)

Sample code to add the Vala language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'valals',
                 \   filetype: 'vala',
                 \   path: 'vala-language-server',
                 \   args: []
                 \ }])
```

<a name="verible"/></a>
## Verible
**Language**: Verilog/SystemVerilog

**Home Page**: [https://github.com/chipsalliance/verible](https://github.com/chipsalliance/verible)

Sample code to add the Vimscript language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'verible',
                 \   filetype: ['verilog', 'systemverilog'],
                 \   path: 'verible-verilog-ls',
                 \   args: ['']
                 \ }])
```

<a name="vhdl-language-server"/></a>
## VHDL Language Server
**Language**: VHDL

**Home Page**: [https://github.com/VHDL-LS/rust_hdl](https://github.com/VHDL-LS/rust_hdl)

Sample code to add the language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'vhdl_ls',
                 \   filetype: 'vhdl',
                 \   path: 'vhdl_ls',
                 \ }])
```

<a name="vim-language-server"/></a>
## Vimscript
**Language**: Vimscript

**Home Page**: [https://github.com/iamcco/vim-language-server](https://github.com/iamcco/vim-language-server)

Sample code to add the Vimscript language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'vimls',
                 \   filetype: 'vim',
                 \   path: '/usr/local/bin/vim-language-server',
                 \   args: ['--stdio']
                 \ }])
```

<a name="volar-server"/></a>
## Volar Server
**Language**: Vue

**Home Page**: [https://github.com/vuejs/language-tools](https://github.com/vuejs/language-tools)

Sample code to add the Volar language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'volar-server',
                 \   filetype: ['vue', 'typescript'],
                 \   path: '/usr/local/node_modules/.bin/volar-server',
                 \   args: ['--stdio'],
                 \   initializationOptions: #{
                 \       typescript: #{
                 \           tsdk: '/usr/local/node_modules/typescript/lib'
                 \       }
                 \   }
                 \ }])
```

For Volar 2:
```vim
call LspAddServer([#{name: 'vue-ls',
                 \   filetype: ['vue'],
                 \   path: 'vue-language-server',
                 \   args: ['--stdio'],
                 \   initializationOptions: #{
                 \       typescript: #{
                 \           tsdk: '/usr/local/node_modules/typescript/lib'
                 \       },
                 \       vue: #{
                 \           hybridMode: v:false
                 \       }
                 \   }
                 \ }])
```
_Note_: The `hybridMode` item in `initializationOptions` is needed if you are using version >= 2.0.7.

<a name="vscode-css-lsp"/></a>
## VS Code CSS Language Server
**Language**: CSS

**Home Page**: [https://github.com/hrsh7th/vscode-langservers-extracted](https://github.com/hrsh7th/vscode-langservers-extracted)

Sample code to add the VS Code CSS language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'vscode-css-server',
                 \   filetype: ['css'],
                 \   path: '/usr/local/node_modules/.bin/vscode-css-language-server',
                 \   args: ['--stdio'],
                 \ }])
```

<a name="vscode-eslint-lsp"/></a>
## VS Code ESLint Language Server
**Language**: Javascript

**Home Page**: [https://github.com/hrsh7th/vscode-langservers-extracted](https://github.com/hrsh7th/vscode-langservers-extracted)

Sample code to add the VS Code ESLint language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'vscode-eslint-server',
                 \   filetype: ['javascript'],
                 \   path: '/usr/local/node_modules/.bin/vscode-eslint-language-server',
                 \   args: ['--stdio'],
                 \ }])
```

<a name="vscode-html-lsp"/></a>
## VS Code HTML Language Server
**Language**: HTML

**Home Page**: [https://github.com/hrsh7th/vscode-langservers-extracted](https://github.com/hrsh7th/vscode-langservers-extracted)

Sample code to add the VS Code HTML language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'vscode-html-server',
                 \   filetype: ['html'],
                 \   path: '/usr/local/node_modules/.bin/vscode-html-language-server',
                 \   args: ['--stdio'],
                 \ }])
```

<a name="vscode-json-lsp"/></a>
## VS Code JSON Language Server
**Language**: JSON

**Home Page**: [https://github.com/hrsh7th/vscode-langservers-extracted](https://github.com/hrsh7th/vscode-langservers-extracted)

Sample code to add the VS Code JSON language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'vscode-json-server',
                 \   filetype: ['json'],
                 \   path: '/usr/local/node_modules/.bin/vscode-json-language-server',
                 \   args: ['--stdio'],
                 \   initializationOptions: #{ provideFormatter: v:true }
                 \ }])
```
_Note_: The JSON language server supports code completion only if the _snippetSupport_ option is enabled.

<a name="vscode-markdown-lsp"/></a>
## VS Code Markdown Language Server
**Language**: markdown

**Home Page**: [https://github.com/hrsh7th/vscode-langservers-extracted](https://github.com/hrsh7th/vscode-langservers-extracted)

Sample code to add the VS Code Markdown language server to the LSP plugin:
```vim
call LspAddServer([#{name: 'vscode-markdown-server',
                 \   filetype: ['markdown'],
                 \   path: '/usr/local/node_modules/.bin/vscode-markdown-language-server',
                 \   args: ['--stdio'],
                 \ }])
```

<a name="yaml-language-server"/></a>
## YAML Language Server
**Language**: YAML

**Home Page**: https://github.com/redhat-developer/yaml-language-server

Sample code to add the YAML Language Server to the LSP plugin:
```vim
call LspAddServer([#{
            \   name: 'yaml-language-server',
            \   filetype: 'yaml',
            \   path: '/usr/local/node_modules/.bin/yaml-language-server',
            \   args: ['--stdio'],
            \   workspaceConfig: #{
            \       yaml: #{
            \           schemas: {
            \               "https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json" : [
            \                   "**/*docker-compose*.yaml"
            \               ],
            \              "https://json.schemastore.org/chart.json": [
            \                   "**helm/values*.yaml"
            \               ]
            \           }
            \       }
            \   }
            \ }])
```
**Note**: The workspaceConfig `yaml.schemas` object is a key-value pair where the key is a link or path to a yaml schema and the value is an array of file path patterns to enforce the schema on. There can be any number of enforced schemas based on a user's need, but I have given examples based on enforcing the compose spec and adding helm chart suggestions for configuration.
