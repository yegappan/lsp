vim9script

if get(b:, 'markdown_fallback', v:false)
  runtime! syntax/markdown.vim
  finish
endif

var group: dict<string> = {}
for region in get(b:, 'lsp_syntax', [])
  if !group->has_key(region.lang)
    group[region.lang] = region.lang->substitute('\(^.\|_\a\)', '\u&', 'g')
    try
      exe $'syntax include @{group[region.lang]} syntax/{region.lang}.vim'
    catch /.*/
      group[region.lang] = ''
    endtry
  endif
  if !group[region.lang]->empty()
    exe $'syntax region lspCodeBlock start="{region.start}" end="{region.end}" contains=@{group[region.lang]}'
  endif
endfor

# vim: tabstop=8 shiftwidth=2 softtabstop=2
