" ------------------------------------------------------
" This file contains the core functions of the plugin. 
" ------------------------------------------------------

" Function to retrieve the GitHub Token:
function! gh_review#get_token() abort
	let token_file = expand(g:gh_review_token_file)
	if filereadable(token_file)
		return trim(readfile(token_file)[0])
	endif

	call gh_review#set_token()
	if filereadable(token_file)
		return trim(readfile(token_file)[0])
	endif

	throw "GitHub token not found! Please run :GHSetToken first."
endfunction


" --------------------------------------------------------


" Function to set GitHub Token:
function! gh_review#set_token() abort
	echohl Question
	let token = input("Enter your GitHub PAT: ")
	echohl None

	if empty(token)
		echohl ErrorMsg
		echom "Token can not be empty!"
		echohl None
		return
	endif

	call writefile([token], expand(g:gh_review_token_file))
	" Use system call for file permissions which is more reliable
	if has('unix')
		call system('chmod 600 ' . shellescape(expand(g:gh_review_token_file)))
	elseif has('win32')
		" On Windows, just make the file hidden
		call system('attrib +h ' . shellescape(expand(g:gh_review_token_file)))
	endif
	echom "GitHub token saved successfully!"
endfunction

" Add the missing setup_token function that matches command call
function! gh_review#setup_token() abort
	call gh_review#set_token()
endfunction

" Get current repository information
function! gh_review#get_repo_info() abort
	" Try to get repo from git remote
	let remote_url = system('git config --get remote.origin.url')
	if v:shell_error != 0
		throw "Not in a git repository or no origin remote!"
	endif

	" Parse owner and repo from remote URL
	let remote_url = trim(remote_url)
	let pattern = '.\+github\.com[:/]\([^/]\+\)/\([^/]\+\)\(\.git\)\?$'
	let owner = substitute(remote_url, pattern, '\1', '')
	let repo = substitute(remote_url, pattern, '\2', '')

	" Remove .git suffix if present
	let repo = substitute(repo, '\.git$', '', '')

	return {'owner': owner, 'repo': repo}
endfunction

" List pull requests
function! gh_review#list_prs() abort
	try
		let token = gh_review#get_token()
		let repo_info = gh_review#get_repo_info()

		echom "Fetching PRs for " . repo_info.owner . "/" . repo_info.repo . "..."

		let cmd = ['curl', '-s', '-H', 'Authorization: token ' . token,
					\ 'https://api.github.com/repos/' . repo_info.owner . '/' . repo_info.repo . '/pulls?state=open']

		let result = system(join(cmd, ' '))
		if v:shell_error != 0
			throw "Failed to fetch PRs: " . result
		endif

		try
			let prs = json_decode(result)
		catch
			throw "Invalid JSON response from GitHub API: " . result
		endtry

		if empty(prs)
			echom "No open PRs found!"
			return
		endif

		" Create new buffer for PR list
		silent! execute 'new [GH-PR-List]'
		setlocal buftype=nofile bufhidden=wipe noswapfile nowrap
		setlocal filetype=gh_pr_list

		" Populate buffer with PR info
		call setline(1, "# Open Pull Requests for " . repo_info.owner . "/" . repo_info.repo)
		call append(line('$'), "")

		let idx = 1
		for pr in prs
			let line = printf("%d. #%d: %s", idx, pr.number, pr.title)
			call append(line('$'), line)
			let idx += 1
		endfor

		" Add mappings for the PR list buffer
		nnoremap <buffer> <CR> :call <SID>review_pr_under_cursor()<CR>

		" Store PR data for later use
		let b:gh_prs = prs

		" Move cursor to first PR
		normal! 3G

	catch
		echohl ErrorMsg
		echom v:exception
		echohl None
	endtry
endfunction

" Helper function to review PR under cursor
function! s:review_pr_under_cursor() abort
	if !exists('b:gh_prs')
		echohl ErrorMsg
		echom "PR data not available!"
		echohl None
		return
	endif

	let line_text = getline('.')
	let pr_idx_match = matchlist(line_text, '^\(\d\+\)\.')

	if empty(pr_idx_match)
		echohl ErrorMsg
		echom "No PR found under cursor!"
		echohl None
		return
	endif

	let pr_idx = str2nr(pr_idx_match[1]) - 1
	if pr_idx >= 0 && pr_idx < len(b:gh_prs)
		let pr_number = b:gh_prs[pr_idx].number
		call gh_review#review(pr_number)
	endif
endfunction

" Review a specific PR
function! gh_review#review(pr_number) abort
	try
		let token = gh_review#get_token()
		let repo_info = gh_review#get_repo_info()

		" Get PR details
		let cmd = ['curl', '-s', '-H', 'Authorization: token ' . token,
					\ 'https://api.github.com/repos/' . repo_info.owner . '/' . repo_info.repo . '/pulls/' . a:pr_number]

		let result = system(join(cmd, ' '))
		if v:shell_error != 0
			throw "Failed to fetch PR details: " . result
		endif

		try
			let pr = json_decode(result)
		catch
			throw "Invalid JSON response from GitHub API: " . result
		endtry

		" Get PR diff
		let cmd = ['curl', '-s', '-H', 'Authorization: token ' . token,
					\ '-H', 'Accept: application/vnd.github.v3.diff',
					\ 'https://api.github.com/repos/' . repo_info.owner . '/' . repo_info.repo . '/pulls/' . a:pr_number]

		let diff = system(join(cmd, ' '))
		if v:shell_error != 0
			throw "Failed to fetch PR diff: " . diff
		endif

		" Create new buffer for PR review
		silent! execute 'new [GH-PR-#' . a:pr_number . ']'
		setlocal buftype=nofile bufhidden=wipe noswapfile
		setlocal filetype=diff

		" Store PR info
		let b:gh_pr = pr
		let b:gh_pr_number = a:pr_number
		let b:gh_repo_info = repo_info

		" Add PR metadata at the top
		call setline(1, "# PR #" . a:pr_number . ": " . pr.title)
		call append(line('$'), "Author: " . pr.user.login)
		call append(line('$'), "Branch: " . pr.head.ref . " → " . pr.base.ref)
		call append(line('$'), "")
		call append(line('$'), pr.body)
		call append(line('$'), "")
		call append(line('$'), "---")
		call append(line('$'), "")

		" Add diff content
		let diff_lines = split(diff, '\n')
		call append(line('$'), diff_lines)

		" Add mappings for the PR review buffer
		nnoremap <buffer> <leader>c :call gh_review#comment('')<CR>
		nnoremap <buffer> <leader>a :call gh_review#approve(b:gh_pr_number)<CR>
		nnoremap <buffer> <leader>r :call gh_review#request_changes(b:gh_pr_number)<CR>
		nnoremap <buffer> <leader>m :call gh_review#merge(b:gh_pr_number)<CR>

		" Move cursor to the start of the diff
		normal! 9G

	catch
		echohl ErrorMsg
		echom v:exception
		echohl None
	endtry
endfunction

" Add a comment to the PR
function! gh_review#comment(...) abort
	if !exists('b:gh_pr_number') || !exists('b:gh_repo_info')
		echohl ErrorMsg
		echom "Not in a PR review buffer!"
		echohl None
		return
	endif

	let current_line = line('.')
	let path = ''
	let line_number = ''

	" Try to determine file path and line number from diff
	let idx = current_line
	while idx > 0
		let line_text = getline(idx)
		if line_text =~# '^diff --git'
			let path_match = matchlist(line_text, 'diff --git a/\S\+ b/\(\S\+\)')
			if !empty(path_match)
				let path = path_match[1]
			endif
			break
		elseif line_text =~# '^@@ '
			let hunk_match = matchlist(line_text, '@@ -\d\+,\d\+ +\(\d\+\)')
			if !empty(hunk_match)
				" Calculate line number in the new file
				let hunk_start = str2nr(hunk_match[1])
				let lines_from_hunk = current_line - idx - 1
				let line_number = hunk_start + lines_from_hunk
			endif
		endif
		let idx -= 1
	endwhile

	echohl Question
	let comment_text = input('Comment: ')
	echohl None

	if empty(comment_text)
		echom "Comment cancelled."
		return
	endif

	try
		let token = gh_review#get_token()

		" Create the comment payload
		if !empty(path) && !empty(line_number)
			" File-specific comment
			let payload = {
						\ 'body': comment_text,
						\ 'commit_id': b:gh_pr.head.sha,
						\ 'path': path,
						\ 'line': line_number
						\ }

			let endpoint = 'https://api.github.com/repos/' . b:gh_repo_info.owner . '/' . b:gh_repo_info.repo .
						\ '/pulls/' . b:gh_pr_number . '/comments'
		else
			" General PR comment
			let payload = {'body': comment_text}
			let endpoint = 'https://api.github.com/repos/' . b:gh_repo_info.owner . '/' . b:gh_repo_info.repo .
						\ '/issues/' . b:gh_pr_number . '/comments'
		endif

		let json_payload = json_encode(payload)
		let cmd = ['curl', '-s', '-X', 'POST', '-H', 'Authorization: token ' . token,
					\ '-H', 'Content-Type: application/json',
					\ '-d', shellescape(json_payload),
					\ endpoint]

		let result = system(join(cmd, ' '))

		if v:shell_error != 0
			throw "Failed to post comment: " . result
		endif

		echom "Comment posted successfully!"

	catch
		echohl ErrorMsg
		echom v:exception
		echohl None
	endtry
endfunction

" Approve a PR
function! gh_review#approve(pr_number) abort
	call s:submit_review(a:pr_number, 'APPROVE')
endfunction

" Request changes on a PR
function! gh_review#request_changes(pr_number) abort
	call s:submit_review(a:pr_number, 'REQUEST_CHANGES')
endfunction

" Helper function to submit a review
function! s:submit_review(pr_number, event) abort
	try
		let token = gh_review#get_token()
		let repo_info = gh_review#get_repo_info()

		echohl Question
		let review_comment = input('Review comment: ')
		echohl None

		if a:event !=# 'APPROVE' && empty(review_comment)
			echom "Review cancelled. A comment is required for this review type."
			return
		endif

		let payload = {
					\ 'event': a:event,
					\ 'body': review_comment
					\ }

		let json_payload = json_encode(payload)
		let endpoint = 'https://api.github.com/repos/' . repo_info.owner . '/' . repo_info.repo .
					\ '/pulls/' . a:pr_number . '/reviews'

		let cmd = ['curl', '-s', '-X', 'POST', '-H', 'Authorization: token ' . token,
					\ '-H', 'Content-Type: application/json',
					\ '-d', shellescape(json_payload),
					\ endpoint]

		let result = system(join(cmd, ' '))

		if v:shell_error != 0
			throw "Failed to submit review: " . result
		endif

		echom "Review submitted successfully!"

	catch
		echohl ErrorMsg
		echom v:exception
		echohl None
	endtry
endfunction

" Merge a PR
function! gh_review#merge(pr_number) abort
	try
		let token = gh_review#get_token()
		let repo_info = gh_review#get_repo_info()

		echohl Question
		let merge_method = input('Merge method (merge/squash/rebase): ', 'merge')
		echohl None

		if merge_method !~# '\v^(merge|squash|rebase)$'
			echom "Invalid merge method. Must be one of: merge, squash, rebase."
			return
		endif

		echohl Question
		let commit_title = input('Commit title: ')
		let commit_message = input('Commit message (optional): ')
		echohl None

		let payload = {
					\ 'merge_method': merge_method
					\ }

		if !empty(commit_title)
			let payload.commit_title = commit_title
		endif

		if !empty(commit_message)
			let payload.commit_message = commit_message
		endif

		let json_payload = json_encode(payload)
		let endpoint = 'https://api.github.com/repos/' . repo_info.owner . '/' . repo_info.repo .
					\ '/pulls/' . a:pr_number . '/merge'

		let cmd = ['curl', '-s', '-X', 'PUT', '-H', 'Authorization: token ' . token,
					\ '-H', 'Content-Type: application/json',
					\ '-d', shellescape(json_payload),
					\ endpoint]

		let result = system(join(cmd, ' '))

		if v:shell_error != 0
			throw "Failed to merge PR: " . result
		endif

		echom "PR #" . a:pr_number . " merged successfully!"

	catch
		echohl ErrorMsg
		echom v:exception
		echohl None
	endtry
endfunction

" Completion for merge strategies
function! gh_review#complete_merge_strategies(ArgLead, CmdLine, CursorPos) abort
	return filter(['merge', 'squash', 'rebase'], 'v:val =~ "^" . a:ArgLead')
endfunction
