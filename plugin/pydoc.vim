if exists('g:loaded_pydoc')
  finish
endif
let g:loaded_pydoc = 1

lua require('pydoc')
