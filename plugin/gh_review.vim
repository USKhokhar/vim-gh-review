" -----------------------------------------------------------
" | vim-gh-preview -- GitHub PR Review inside Vim           |
" | Maintainer - U.S.Khokhar (GH @USKhokhar, X @US_Khokhar) |
" | Version - 0.1.0                                         |
" -----------------------------------------------------------

if exists('g:loaded_gh_review')
	finish
endif
let g:loadloaded_gh_review = 1

" Configuration variables with defaults

if !exists('g:gh_review_token_file')
	let g:gh_review_token_file = expand('~/.gh_review_token')
endif

if !exists('g:gh_review_cache_dir')
	let g:gh_review_cache_dir = expand('~/.cache/vim-gh-review')
endif

" Create the cache dir if it doesn't exist

if !isdirectory(g:gh_review_cache_dir)
	call mkdir(g:gh_review_cache_dir, 'p')
endif

" -------------------------------
" ---------- COMMANDS -----------
" -------------------------------

command! -nargs=0 GHList call gh_review#list_prs()
command! -nargs=1 GHReview call gh_review#review(<f-args>)
command! -nargs=? GHComment call gh_review#comment(<f-args>)
command! -nargs=1 GHApprove call gh_review#approve(<f-args>)
command! -nargs=1 GHRequest call gh_review#request_changes(<f-args>)
command! -nargs=1 -complete=customlist,gh_review#complete_merge_strategies GHMerge call gh_review#merge(<f-args>)
command! -nargs=0 GHSetToken call gh_review#setup_token()

