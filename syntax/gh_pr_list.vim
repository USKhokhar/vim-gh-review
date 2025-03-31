" Syntax highlighting for GitHub PR List

if exists("b:current_syntax")
  finish
endif

syntax match ghPRHeader /^# .*$/
syntax match ghPRNumber /#\d\+/
syntax match ghPRListIndex /^\d\+\./

highlight link ghPRHeader Title
highlight link ghPRNumber Identifier
highlight link ghPRListIndex Number

let b:current_syntax = "gh_pr_list"
