# Language Server Specific Configuration

Information about using various language servers with the LSP plugin is below.
A sample VimScript code snippet is given for each language server to register the server with the LSP plugin.
A sample absolute path to the language server executable is used in these examples.
You may need to modify the path to match where the language server is installed in your system.
In some cases, it may be simpler to add the language server path to the PATH environment variable.

If your preferred LSP is not found, then possibly it is listed at [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig/blob/master/doc/configs.md) where its `Default config` section can be transferred by setting

- `filetype:` here to the value of `Filetypes` there,
- `path` here to the first entry of `cmd`, and
- `args` here to the subsequent entries of `cmd`.

## Angular Language Server
**Language**: [Angular Templates](https://en.wikipedia.org/wiki/Angular_(web_framework))

**Home Page**: [https://github.com/angular/vscode-ng-language-service](https://github.com/angular/vscode-ng-language-service)

Sample code to add the angular language server to the LSP plugin:
```
call LspAddServer([#{name: 'angular',
                 \   filetype: 'html',
                 \   path: '/usr/local/bin/ngserver.cmd',
                 \   args: ['--stdio', '--ngProbeLocations', '/usr/local/bin/@angular/language-service', '--tsProbeLocations', '/usr/local/bin/typescript']
                 \ }])
```

Command to install the angular language server on Linux:
```
npm install -g @angular/language-server @angular/language-service typescript
```

## AWK Language Server
**Language**: [AWK scripts](https://en.wikipedia.org/wiki/AWK)

**Home Page**: [https://github.com/Beaglefoot/awk-language-server](https://github.com/Beaglefoot/awk-language-server)

Sample code to add the awk language server to the LSP plugin:
```
" Awk
call LspAddServer([#{name: 'awkls',
                 \   filetype: 'awk',
                 \   path: '/usr/local/bin/awk-language-server',
                 \   args: []
                 \ }])
```

Command to install the awk language server on Linux:
```
npm install -g awk-language-server
```

## Bash Language Server
**Language**: [Bash shell scripts](https://en.wikipedia.org/wiki/Bash_(Unix_shell))

**Home Page**: [https://github.com/bash-lsp/bash-language-server](https://github.com/bash-lsp/bash-language-server)

Sample code to add the bash language server to the LSP plugin:
```
" Bash
call LspAddServer([#{name: 'bashls',
                 \   filetype: 'sh',
                 \   path: '/usr/local/bin/bash-language-server',
                 \   args: ['start']
                 \ }])
```

## Clangd
**Language**: C/C++

**Home Page**: [https://clangd.llvm.org/](https://clangd.llvm.org/)

Sample code to add the clangd language server to the LSP plugin:
```
call LspAddServer([#{name: 'clangd',
                 \   filetype: ['c', 'cpp'],
                 \   path: '/usr/local/bin/clangd',
                 \   args: ['--background-index', '--clang-tidy']
                 \ }])
```

## CSS Language Server
**Language**: CSS

**Home Page**: [https://github.com/vscode-langservers/vscode-css-languageserver-bin](https://github.com/vscode-langservers/vscode-css-languageserver-bin)

Sample code to add the CSS language server to the LSP plugin:
```
call LspAddServer([#{name: 'cssls',
                 \   filetype: 'css',
                 \   path: '/usr/local/node_modules/.bin/css-languageserver',
                 \   args: ['--stdio'],
                 \ }])
```

_Note_: The CSS language server supports code completion only if the _snippetSupport_ option is enabled.

## Dart

**Language**: Dart

**Home Page**: [https://github.com/dart-lang/sdk/blob/main/pkg/analysis_server/tool/lsp_spec/README.md](https://github.com/dart-lang/sdk/blob/main/pkg/analysis_server/tool/lsp_spec/README.md)

Sample code to add the dart language server to the LSP plugin:

```
call LspAddServer([#{name: 'dart',
                 \   filetype: ['dart'],
                 \   path: '/usr/lib/dart/bin/dart',
                 \   args: ['language-server', '--client-id', 'vim']
                 \ }])
```

## Deno
**Language**: Typescript/Javascript

**Home Page**: [https://deno.land](https://deno.land)

Sample code to add the deno language server to the LSP plugin:
```
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

## Eclipse Java Language Server
**Language**: Java

**Home Page**: [https://github.com/eclipse/eclipse.jdt.ls](https://github.com/eclipse/eclipse.jdt.ls)

Sample code to add the Eclipse Java Development Tools (JDT) language server to the LSP plugin:
```
call LspAddServer([#{name: 'jdtls',
                 \   filetype: 'java',
                 \   path: '/usr/local/jdtls/bin/jdtls',
                 \   args: []
                 \   initializationOptions: {
                 \       settings: {
                 \           java: {
                 \               completion: {
                 \                   filteredTypes: ["com.sun.*", "java.awt.*", "jdk.*", "org.graalvm.*", "sun.*", "javax.awt.*", "javax.swing.*"],
                 \               },
                 \           },
                 \       },
                 \   },
                 \ }])
```

The [Eclipse Java language server wiki page](https://github.com/eclipse/eclipse.jdt.ls/wiki/Running-the-JAVA-LS-server-from-the-command-line#initialize-request) has more information about the jdtls language server initialization options.  In the above example, the `filteredTypes` item is not mandatory to use the JDT language server with the LSP plugin.  It is included here only as an example.

## EFM Language Server
**Language**: General Purpose Language Server

**Home Page**: [https://github.com/mattn/efm-langserver](https://github.com/mattn/efm-langserver)

Sample code to add the efm language server to the LSP plugin:
```
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

## Emmet Language Server
**Language**: HTML

**Home Page**: [https://github.com/olrtg/emmet-language-server](https://github.com/olrtg/emmet-language-server)

Sample code to add the emmet language server to the LSP plugin:
```
call LspAddServer([#{name: 'emmet',
                 \   filetype: 'html',
                 \   path: '/usr/local/node_modules/.bin/emmet-language-server',
                 \   args: ['--stdio'],
                 \ }])
```

Command to install the emmet language server on Linux:
```
npm install -g @olrtg/emmet-language-server
```

## Fortran Language Server
**Language**: Fortran

**Home Page**: [https://github.com/hansec/fortran-language-server](https://github.com/hansec/fortran-language-server)

Sample code to add the fortran language server to the LSP plugin:
```
call LspAddServer([#{name: 'fortls',
                 \   filetype: 'fortran',
                 \   path: '/usr/local/bin/fortls',
                 \   args: ['--use_signature_help', '--hover_signature']
                 \ }])
```

## Gopls
**Language**: Go

**Home Page**: [https://github.com/golang/tools/tree/master/gopls](https://github.com/golang/tools/tree/master/gopls)

Sample code to add the gopls language server to the LSP plugin:
```
call LspAddServer([#{name: 'gopls',
                 \   filetype: 'go',
                 \   path: '/usr/local/bin/gopls',
                 \   args: ['serve']
                 \ }])
```

**Server Configuration**: [https://github.com/golang/tools/blob/master/gopls/doc/settings.md](https://github.com/golang/tools/blob/master/gopls/doc/settings.md)

To enable the inlay hint support, include the following in the above code to add the gopls language server:
```
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

## HTML Language Server
**Language**: html

**Home Page**: [https://github.com/vscode-langservers/vscode-html-languageserver-bin](https://github.com/vscode-langservers/vscode-html-languageserver-bin)

Sample code to add the HTML language server to the LSP plugin:
```
call LspAddServer([#{name: 'htmlls',
                 \   filetype: 'html',
                 \   path: '/usr/local/node_modules/.bin/html-languageserver',
                 \   args: ['--stdio'],
                 \ }])
```

_Note_: The HTML language server supports code completion only if the _snippetSupport_ option is enabled.

## Lua Language Server
**Language**: Lua

**Home Page**: [https://github.com/LuaLS/lua-language-server](https://github.com/LuaLS/lua-language-server)

Sample code to add the luals language server to the LSP plugin:
```
call LspAddServer([#{name: 'luals',
                 \   filetype: 'lua',
                 \   path: '/usr/local/luals/bin/lua-language-server',
                 \   args: [],
                 \ }])
```
**Server Configuration**: [https://github.com/LuaLS/lua-language-server/wiki/Settings](https://github.com/LuaLS/lua-language-server/wiki/Settings)

To enable the inlay hint support, include the following in the above code to add the Lua language server:
```
    \   workspaceConfig: #{
    \     Lua: #{
    \       hint: #{
    \         enable: v:true,
    \       }
    \     }
    \   }
```

## Omnisharp Language Server
**Language**: C#

**Home Page**: [https://github.com/OmniSharp/omnisharp-roslyn](https://github.com/OmniSharp/omnisharp-roslyn)

Sample code to add the omnisharp language server to the LSP plugin:
```
call LspAddServer([#{name: 'omnisharp',
                 \   filetype: 'cs',
                 \   path: expand('$HOME/omnisharp/omnisharp.exe'),
                 \   args: ['-z', '--languageserver', '--encoding', 'utf-8'],
                 \ }])
```

## Perl Navigator
**Language**: Perl

**Home Page**: [https://github.com/bscan/PerlNavigator](https://github.com/bscan/PerlNavigator)

Sample code to add the Perl Navigator language server to the LSP plugin:
```
call LspAddServer([#{name: 'perlnavigator',
                 \   filetype: ['perl'],
                 \   path: '/usr/bin/node',
                 \   args: ['/usr/local/PerlNavigator/server/out/server.js', '--stdio']
                 \ }])
```

## PHP Intelephense
**Language**: PHP

**Home Page**: [https://github.com/bmewburn/vscode-intelephense](https://github.com/bmewburn/vscode-intelephense)

Sample code to add the intelephense language server to the LSP plugin:
```
call LspAddServer([#{name: 'intelephense',
                 \   filetype: ['php'],
                 \   path: '/usr/local/bin/intelephense',
                 \   args: ['--stdio']
                 \ }])
```

## Pylsp
**Language**: Python

**Home Page**: [https://github.com/python-lsp/python-lsp-server](https://github.com/python-lsp/python-lsp-server)

Sample code to add the pylsp language server to the LSP plugin:
```
call LspAddServer([#{name: 'pylsp',
                 \   filetype: 'python',
                 \   path: '/usr/local/bin/pylsp',
                 \   args: []
                 \ }])
```

## Pyright
**Language**: Python

**Home Page**: [https://github.com/microsoft/pyright](https://github.com/microsoft/pyright)

Sample code to add the pyright language server to the LSP plugin:
```
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
```
   $ npm install -g pyright
```

**Server Configuration**: [https://microsoft.github.io/pyright/#/configuration](https://microsoft.github.io/pyright/#/configuration)

## Rust-analyzer
**Language**: Rust

**Home Page**: [https://rust-analyzer.github.io/](https://rust-analyzer.github.io/)

Sample code to add the rust-analyzer language server to the LSP plugin:
```
call LspAddServer([#{name: 'rustanalyzer',
                 \   filetype: ['rust'],
                 \   path: '/usr/local/bin/rust-analyzer-x86_64-unknown-linux-gnu',
                 \   args: [],
                 \   syncInit: v:true
                 \ }])
```

**Server Configuration**: [https://rust-analyzer.github.io/manual.html#configuration](https://rust-analyzer.github.io/manual.html#configuration)

To enable the inlay hint support, include the following in the above code to add the rust-analyzer language server:
```
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

## Solargraph
**Language**: Ruby

**Home Page**: [https://solargraph.org/](https://solargraph.org/)

Sample code to add the Solargraph language server to the LSP plugin:
```
call LspAddServer([#{name: 'solargraph'
                 \   filetype: ['ruby'],
                 \   path: 'solargraph',
                 \   args: ['stdio']
                 \ }])
```

## Swift Language Server
**Language**: [Swift](https://www.swift.org/)

**Home Page**: [https://github.com/apple/sourcekit-lsp](https://github.com/apple/sourcekit-lsp)

Sample code to add the swift language server to the LSP plugin:
```
call LspAddServer([#{name: 'swiftls'
                 \   filetype: ['swift'],
                 \   path: '/usr/bin/xcrun',
                 \   args: ['sourcekit-lsp']
                 \ }])
```

## Typescript/Javascript Language Server
**Language**: Typescript/JavaScript

**Home Page**: [https://github.com/typescript-language-server/typescript-language-server](https://github.com/typescript-language-server/typescript-language-server)

Sample code to add the typescript/javascript language server to the LSP plugin:
```
call LspAddServer([#{name: 'tsserver'
                 \   filetype: ['javascript', 'typescript'],
                 \   path: '/usr/local/bin/typescript-language-server',
                 \   args: ['--stdio']
                 \ }])
```

## Verible
**Language**: Verilog/SystemVerilog

**Home Page**: [https://github.com/chipsalliance/verible](https://github.com/chipsalliance/verible)

Sample code to add the Vimscript language server to the LSP plugin:
```
call LspAddServer([#{name: 'verible',
                 \   filetype: ['verilog', 'systemverilog'],
                 \   path: 'verible-verilog-ls',
                 \   args: ['']
                 \ }])
```

## Vimscript
**Language**: Vimscript

**Home Page**: [https://github.com/iamcco/vim-language-server](https://github.com/iamcco/vim-language-server)

Sample code to add the Vimscript language server to the LSP plugin:
```
call LspAddServer([#{name: 'vimls',
                 \   filetype: 'vim',
                 \   path: '/usr/local/bin/vim-language-server',
                 \   args: ['--stdio']
                 \ }])
```

## Volar Server
**Language**: Vue

**Home Page**: [https://github.com/vuejs/language-tools](https://github.com/vuejs/language-tools)

Sample code to add the Volar language server to the LSP plugin:
```
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
```
call LspAddServer([#{name: 'vue-ls',
                 \   filetype: ['vue'],
                 \   path: 'vue-language-server',
                 \   args: ['--stdio'],
                 \   initializationOptions: #{
                 \       typescript: #{
                 \           tsdk: '/usr/local/node_modules/typescript/lib'
                 \       }
                 \       vue: #{
                 \           hybridMode: v:false
                 \       }
                 \   }
                 \ }])
```
_Note_: The `hybridMode` item in `initializationOptions` is needed if you are using version >= 2.0.7.

## VS Code CSS Language Server
**Language**: CSS

**Home Page**: [https://github.com/hrsh7th/vscode-langservers-extracted](https://github.com/hrsh7th/vscode-langservers-extracted)

Sample code to add the VS Code CSS language server to the LSP plugin:
```
call LspAddServer([#{name: 'vscode-css-server',
                 \   filetype: ['css'],
                 \   path: '/usr/local/node_modules/.bin/vscode-css-language-server',
                 \   args: ['--stdio'],
                 \ }])
```

## VS Code ESLint Language Server
**Language**: Javascript

**Home Page**: [https://github.com/hrsh7th/vscode-langservers-extracted](https://github.com/hrsh7th/vscode-langservers-extracted)

Sample code to add the VS Code ESLint language server to the LSP plugin:
```
call LspAddServer([#{name: 'vscode-eslint-server',
                 \   filetype: ['javascript'],
                 \   path: '/usr/local/node_modules/.bin/vscode-eslint-language-server',
                 \   args: ['--stdio'],
                 \ }])
```

## VS Code HTML Language Server
**Language**: HTML

**Home Page**: [https://github.com/hrsh7th/vscode-langservers-extracted](https://github.com/hrsh7th/vscode-langservers-extracted)

Sample code to add the VS Code HTML language server to the LSP plugin:
```
call LspAddServer([#{name: 'vscode-html-server',
                 \   filetype: ['html'],
                 \   path: '/usr/local/node_modules/.bin/vscode-html-language-server',
                 \   args: ['--stdio'],
                 \ }])
```

## VS Code JSON Language Server
**Language**: JSON

**Home Page**: [https://github.com/hrsh7th/vscode-langservers-extracted](https://github.com/hrsh7th/vscode-langservers-extracted)

Sample code to add the VS Code JSON language server to the LSP plugin:
```
call LspAddServer([#{name: 'vscode-json-server',
                 \   filetype: ['json'],
                 \   path: '/usr/local/node_modules/.bin/vscode-json-language-server',
                 \   args: ['--stdio'],
                 \ }])
```

## VS Code Markdown Language Server
**Language**: markdown

**Home Page**: [https://github.com/hrsh7th/vscode-langservers-extracted](https://github.com/hrsh7th/vscode-langservers-extracted)

Sample code to add the VS Code Markdown language server to the LSP plugin:
```
call LspAddServer([#{name: 'vscode-markdown-server',
                 \   filetype: ['markdown'],
                 \   path: '/usr/local/node_modules/.bin/vscode-markdown-language-server',
                 \   args: ['--stdio'],
                 \ }])
```

## YAML Language Server
**Language**: YAML

**Home Page**: https://github.com/redhat-developer/yaml-language-server

Sample code to add the YAML Language Server to the LSP plugin:
```
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
