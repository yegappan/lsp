vim9script
# Unit tests for language server protocol offset encoding using clangd

source common.vim

# Start the C language server.  Returns true on success and false on failure.
def g:StartLangServer(): bool
  if has('patch-9.0.1629')
    return g:StartLangServerWithFile('Xtest.c')
  endif
  return false
enddef

if !has('patch-9.0.1629')
  # Need patch 9.0.1629 to properly encode/decode the UTF-16 offsets
  finish
endif

var lspOpts = {autoComplete: false}
g:LspOptionsSet(lspOpts)

var lspServers = [{
      filetype: ['c', 'cpp'],
      path: (exepath('clangd-15') ?? exepath('clangd')),
      args: ['--background-index',
	     '--clang-tidy',
	     $'--offset-encoding={$LSP_OFFSET_ENCODING}']
  }]
call LspAddServer(lspServers)

# Test for :LspCodeAction with symbols containing multibyte and composing
# characters
def g:Test_LspCodeAction_multibyte()
  silent! edit XLspCodeAction_mb.c
  sleep 200m
  var lines =<< trim END
    #include <stdio.h>
    void fn(int aVar)
    {
        printf("aVar = %d\n", aVar);
        printf("😊😊😊😊 = %d\n", aVar):
        printf("áb́áb́ = %d\n", aVar):
        printf("ą́ą́ą́ą́ = %d\n", aVar):
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(3)
  :redraw!
  cursor(5, 5)
  redraw!
  :LspCodeAction 1
  assert_equal('    printf("😊😊😊😊 = %d\n", aVar);', getline(5))
  cursor(6, 5)
  redraw!
  :LspCodeAction 1
  assert_equal('    printf("áb́áb́ = %d\n", aVar);', getline(6))
  cursor(7, 5)
  redraw!
  :LspCodeAction 1
  assert_equal('    printf("ą́ą́ą́ą́ = %d\n", aVar);', getline(7))

  :%bw!
enddef

# Test for ":LspDiag show" when using multibyte and composing characters
def g:Test_LspDiagShow_multibyte()
  :silent! edit XLspDiagShow_mb.c
  sleep 200m
  var lines =<< trim END
    #include <stdio.h>
    void fn(int aVar)
    {
        printf("aVar = %d\n", aVar);
        printf("😊😊😊😊 = %d\n". aVar);
        printf("áb́áb́ = %d\n". aVar);
        printf("ą́ą́ą́ą́ = %d\n". aVar);
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(3)
  :redraw!
  :LspDiag show
  var qfl: list<dict<any>> = getloclist(0)
  assert_equal([5, 37], [qfl[0].lnum, qfl[0].col])
  assert_equal([6, 33], [qfl[1].lnum, qfl[1].col])
  assert_equal([7, 41], [qfl[2].lnum, qfl[2].col])
  :lclose
  :%bw!
enddef

# Test for :LspFormat when using multibyte and composing characters
def g:Test_LspFormat_multibyte()
  :silent! edit XLspFormat_mb.c
  sleep 200m
  var lines =<< trim END
    void fn(int aVar)
    {
	int 😊😊😊😊   =   aVar + 1;
	int áb́áb́   =   aVar + 1;
	int ą́ą́ą́ą́   =   aVar + 1;
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(0)
  :redraw!
  :LspFormat
  var expected =<< trim END
    void fn(int aVar) {
      int 😊😊😊😊 = aVar + 1;
      int áb́áb́ = aVar + 1;
      int ą́ą́ą́ą́ = aVar + 1;
    }
  END
  assert_equal(expected, getline(1, '$'))
  :%bw!
enddef

# Test for :LspGotoDefinition when using multibyte and composing characters
def g:Test_LspGotoDefinition_multibyte()
  :silent! edit XLspGotoDefinition_mb.c
  sleep 200m
  var lines: list<string> =<< trim END
    #include <stdio.h>
    void fn(int aVar)
    {
        printf("aVar = %d\n", aVar);
        printf("😊😊😊😊 = %d\n", aVar);
        printf("áb́áb́ = %d\n", aVar);
        printf("ą́ą́ą́ą́ = %d\n", aVar);
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(0)
  redraw!

  for [lnum, colnr] in [[4, 27], [5, 39], [6, 35], [7, 43]]
    cursor(lnum, colnr)
    :LspGotoDefinition
    assert_equal([2, 13], [line('.'), col('.')])
  endfor

  :%bw!
enddef

# Test for :LspGotoDefinition when using multibyte and composing characters
def g:Test_LspGotoDefinition_after_multibyte()
  :silent! edit XLspGotoDef_after_mb.c
  sleep 200m
  var lines =<< trim END
    void fn(int aVar)
    {
        /* αβγδ, 😊😊😊😊, áb́áb́, ą́ą́ą́ą́ */ int αβγδ, bVar;
        /* αβγδ, 😊😊😊😊, áb́áb́, ą́ą́ą́ą́ */ int 😊😊😊😊, cVar;
        /* αβγδ, 😊😊😊😊, áb́áb́, ą́ą́ą́ą́ */ int áb́áb́, dVar;
        /* αβγδ, 😊😊😊😊, áb́áb́, ą́ą́ą́ą́ */ int ą́ą́ą́ą́, eVar;
        bVar = 1;
        cVar = 2;
        dVar = 3;
        eVar = 4;
	aVar = αβγδ + 😊😊😊😊 + áb́áb́ + ą́ą́ą́ą́ + bVar;
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(0)
  :redraw!
  cursor(7, 5)
  :LspGotoDefinition
  assert_equal([3, 88], [line('.'), col('.')])
  cursor(8, 5)
  :LspGotoDefinition
  assert_equal([4, 96], [line('.'), col('.')])
  cursor(9, 5)
  :LspGotoDefinition
  assert_equal([5, 92], [line('.'), col('.')])
  cursor(10, 5)
  :LspGotoDefinition
  assert_equal([6, 100], [line('.'), col('.')])
  cursor(11, 12)
  :LspGotoDefinition
  assert_equal([3, 78], [line('.'), col('.')])
  cursor(11, 23)
  :LspGotoDefinition
  assert_equal([4, 78], [line('.'), col('.')])
  cursor(11, 42)
  :LspGotoDefinition
  assert_equal([5, 78], [line('.'), col('.')])
  cursor(11, 57)
  :LspGotoDefinition
  assert_equal([6, 78], [line('.'), col('.')])

  :%bw!
enddef

# Test for doing omni completion for symbols with multibyte and composing
# characters
def g:Test_OmniComplete_multibyte()
  :silent! edit XOmniComplete_mb.c
  sleep 200m
  var lines: list<string> =<< trim END
    void Func1(void)
    {
        int 😊😊😊😊, aVar;
        int áb́áb́, bVar;
        int ą́ą́ą́ą́, cVar;
        
        
        
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(0)
  redraw!

  cursor(6, 4)
  feedkeys("aaV\<C-X>\<C-O> = 😊😊\<C-X>\<C-O>;", 'xt')
  assert_equal('    aVar = 😊😊😊😊;', getline('.'))
  cursor(7, 4)
  feedkeys("abV\<C-X>\<C-O> = áb́\<C-X>\<C-O>;", 'xt')
  assert_equal('    bVar = áb́áb́;', getline('.'))
  cursor(8, 4)
  feedkeys("acV\<C-X>\<C-O> = ą́ą́\<C-X>\<C-O>;", 'xt')
  assert_equal('    cVar = ą́ą́ą́ą́;', getline('.'))
  feedkeys("oáb́\<C-X>\<C-O> = ą́ą́\<C-X>\<C-O>;", 'xt')
  assert_equal('    áb́áb́ = ą́ą́ą́ą́;', getline('.'))
  feedkeys("oą́ą́\<C-X>\<C-O> = áb́\<C-X>\<C-O>;", 'xt')
  assert_equal('    ą́ą́ą́ą́ = áb́áb́;', getline('.'))
  :%bw!
enddef

# Test for :LspOutline with multibyte and composing characters
def g:Test_Outline_multibyte()
  silent! edit XLspOutline_mb.c
  sleep 200m
  var lines: list<string> =<< trim END
    typedef void 😊😊😊😊;
    typedef void áb́áb́;
    typedef void ą́ą́ą́ą́;
    
    😊😊😊😊 Func1()
    {
    }
    
    áb́áb́ Func2()
    {
    }
    
    ą́ą́ą́ą́ Func3()
    {
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(0)
  redraw!

  cursor(1, 1)
  :LspOutline
  assert_equal(2, winnr('$'))

  :wincmd w
  cursor(5, 1)
  feedkeys("\<CR>", 'xt')
  assert_equal([2, 5, 18], [winnr(), line('.'), col('.')])

  :wincmd w
  cursor(6, 1)
  feedkeys("\<CR>", 'xt')
  assert_equal([2, 9, 14], [winnr(), line('.'), col('.')])

  :wincmd w
  cursor(7, 1)
  feedkeys("\<CR>", 'xt')
  assert_equal([2, 13, 22], [winnr(), line('.'), col('.')])

  :wincmd w
  cursor(10, 1)
  feedkeys("\<CR>", 'xt')
  assert_equal([2, 1, 14], [winnr(), line('.'), col('.')])

  :wincmd w
  cursor(11, 1)
  feedkeys("\<CR>", 'xt')
  assert_equal([2, 2, 14], [winnr(), line('.'), col('.')])

  :wincmd w
  cursor(12, 1)
  feedkeys("\<CR>", 'xt')
  assert_equal([2, 3, 14], [winnr(), line('.'), col('.')])

  :%bw!
enddef

# Test for :LspRename with multibyte and composing characters
def g:Test_LspRename_multibyte()
  silent! edit XLspRename_mb.c
  sleep 200m
  var lines: list<string> =<< trim END
    #include <stdio.h>
    void fn(int aVar)
    {
        printf("aVar = %d\n", aVar);
        printf("😊😊😊😊 = %d\n", aVar);
        printf("áb́áb́ = %d\n", aVar);
        printf("ą́ą́ą́ą́ = %d\n", aVar);
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(0)
  redraw!
  cursor(2, 12)
  :LspRename bVar
  redraw!
  var expected: list<string> =<< trim END
    #include <stdio.h>
    void fn(int bVar)
    {
        printf("aVar = %d\n", bVar);
        printf("😊😊😊😊 = %d\n", bVar);
        printf("áb́áb́ = %d\n", bVar);
        printf("ą́ą́ą́ą́ = %d\n", bVar);
    }
  END
  assert_equal(expected, getline(1, '$'))
  :%bw!
enddef

# Test for :LspShowReferences when using multibyte and composing characters
def g:Test_LspShowReferences_multibyte()
  :silent! edit XLspShowReferences_mb.c
  sleep 200m
  var lines: list<string> =<< trim END
    #include <stdio.h>
    void fn(int aVar)
    {
        printf("aVar = %d\n", aVar);
        printf("😊😊😊😊 = %d\n", aVar);
        printf("áb́áb́ = %d\n", aVar);
        printf("ą́ą́ą́ą́ = %d\n", aVar);
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(0)
  redraw!
  cursor(4, 27)
  :LspShowReferences
  var qfl: list<dict<any>> = getloclist(0)
  assert_equal([2, 13], [qfl[0].lnum, qfl[0].col])
  assert_equal([4, 27], [qfl[1].lnum, qfl[1].col])
  assert_equal([5, 39], [qfl[2].lnum, qfl[2].col])
  assert_equal([6, 35], [qfl[3].lnum, qfl[3].col])
  assert_equal([7, 43], [qfl[4].lnum, qfl[4].col])
  :lclose

  :%bw!
enddef

# Test for :LspSymbolSearch when using multibyte and composing characters
def g:Test_LspSymbolSearch_multibyte()
  silent! edit XLspSymbolSearch_mb.c
  sleep 200m
  var lines: list<string> =<< trim END
    typedef void 😊😊😊😊;
    typedef void áb́áb́;
    typedef void ą́ą́ą́ą́;

    😊😊😊😊 Func1()
    {
    }

    áb́áb́ Func2()
    {
    }

    ą́ą́ą́ą́ Func3()
    {
    }
  END
  setline(1, lines)
  g:WaitForServerFileLoad(0)

  cursor(1, 1)
  feedkeys(":LspSymbolSearch Func1\<CR>", "xt")
  assert_equal([5, 18], [line('.'), col('.')])
  cursor(1, 1)
  feedkeys(":LspSymbolSearch Func2\<CR>", "xt")
  assert_equal([9, 14], [line('.'), col('.')])
  cursor(1, 1)
  feedkeys(":LspSymbolSearch Func3\<CR>", "xt")
  assert_equal([13, 22], [line('.'), col('.')])

  :%bw!
enddef

# Test for setting the 'tagfunc' with multibyte and composing characters in
# symbols
def g:Test_LspTagFunc_multibyte()
  var lines =<< trim END
    void fn(int aVar)
    {
        int 😊😊😊😊, bVar;
        int áb́áb́, cVar;
        int ą́ą́ą́ą́, dVar;
        bVar = 10;
        cVar = 10;
        dVar = 10;
    }
  END
  writefile(lines, 'Xtagfunc_mb.c')
  :silent! edit! Xtagfunc_mb.c
  g:WaitForServerFileLoad(0)
  :setlocal tagfunc=lsp#lsp#TagFunc
  cursor(6, 5)
  :exe "normal \<C-]>"
  assert_equal([3, 27], [line('.'), col('.')])
  cursor(7, 5)
  :exe "normal \<C-]>"
  assert_equal([4, 23], [line('.'), col('.')])
  cursor(8, 5)
  :exe "normal \<C-]>"
  assert_equal([5, 31], [line('.'), col('.')])
  :set tagfunc&

  :%bw!
  delete('Xtagfunc_mb.c')
enddef

# Test for the :LspSuperTypeHierarchy and :LspSubTypeHierarchy commands with
# multibyte and composing characters
def g:Test_LspTypeHier_multibyte()
  silent! edit XLspTypeHier_mb.cpp
  sleep 200m
  var lines =<< trim END
    /* αβ😊😊ááą́ą́ */ class parent {
    };

    /* αβ😊😊ááą́ą́ */ class child : public parent {
    };

    /* αβ😊😊ááą́ą́ */ class grandchild : public child {
    };
  END
  setline(1, lines)
  g:WaitForServerFileLoad(0)
  redraw!

  cursor(1, 42)
  :LspSubTypeHierarchy
  call feedkeys("\<CR>", 'xt')
  assert_equal([1, 36], [line('.'), col('.')])
  cursor(1, 42)

  :LspSubTypeHierarchy
  call feedkeys("\<Down>\<CR>", 'xt')
  assert_equal([4, 42], [line('.'), col('.')])

  cursor(1, 42)
  :LspSubTypeHierarchy
  call feedkeys("\<Down>\<Down>\<CR>", 'xt')
  assert_equal([7, 42], [line('.'), col('.')])

  cursor(7, 42)
  :LspSuperTypeHierarchy
  call feedkeys("\<CR>", 'xt')
  assert_equal([7, 36], [line('.'), col('.')])

  cursor(7, 42)
  :LspSuperTypeHierarchy
  call feedkeys("\<Down>\<CR>", 'xt')
  assert_equal([4, 36], [line('.'), col('.')])

  cursor(7, 42)
  :LspSuperTypeHierarchy
  call feedkeys("\<Down>\<Down>\<CR>", 'xt')
  assert_equal([1, 36], [line('.'), col('.')])

  :%bw!
enddef

# vim: shiftwidth=2 softtabstop=2 noexpandtab
