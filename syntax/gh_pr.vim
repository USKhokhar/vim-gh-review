" Syntax highlighting for GitHub PR Review

if exists("b:current_syntax")
	finish
endif

" Import markdown syntax for PR description parts
runtime! syntax/markdown.vim
unlet! b:current_syntax

" PR metadata
syntax match ghPRTitle /^# PR #\d\+:.*/
syntax match ghPRMeta /^Author: .*$/
syntax match ghPRMeta /^Branch: .*$/
syntax match ghPRMeta /^Created: .*$/
syntax match ghPRMeta /^URL: .*$/

" Section headers
syntax match ghPRSection /^## .*$/

" File list items
syntax match ghPRFileAdded /^\d\+\. \[+\] .*/
syntax match ghPRFileRemoved /^\d\+\. \[-\] .*/
syntax match ghPRFileModified /^\d\+\. \[M\] .*/
syntax match ghPRFileRenamed /^\d\+\. \[→\] .*/
syntax match ghPRFileOther /^\d\+\. \[•\] .*/

" Review controls
syntax match ghPRControl /^- Press .*/

" Import diff syntax for the diff section
syntax include @Diff syntax/diff.vim
syntax region ghPRDiff start=/^diff --git/ end=/\%$/ contains=@Diff

" Highlight links
highlight link ghPRTitle Title
highlight link ghPRMeta Identifier
highlight link ghPRSection Statement
highlight link ghPRFileAdded DiffAdd
highlight link ghPRFileRemoved DiffDelete
highlight link ghPRFileModified DiffChange
highlight link ghPRFileRenamed Special
highlight link ghPRFileOther Normal
highlight link ghPRControl Comment

let b:current_syntax = "gh_pr"
