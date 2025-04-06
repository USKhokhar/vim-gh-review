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
	let owner = ''
	let repo = ''

	" Handle SSH URL format (git@github.com:user/repo.git or git@custom-host:user/repo.git)
	let ssh_pattern = '^\s*git@.\+:\([^/]\+\)/\([^/]\+\)\(\.git\)\?\s*$'
	if remote_url =~# ssh_pattern
		let owner = substitute(remote_url, ssh_pattern, '\1', '')
		let repo = substitute(remote_url, ssh_pattern, '\2', '')
	else
		" Handle HTTPS URL format (https://github.com/user/repo.git)
		let https_pattern = '.\+github\.com[:/]\([^/]\+\)/\([^/]\+\)\(\.git\)\?$'
		if remote_url =~# https_pattern
			let owner = substitute(remote_url, https_pattern, '\1', '')
			let repo = substitute(remote_url, https_pattern, '\2', '')
		else
			throw "Unsupported git remote format: " . remote_url
		endif
	endif

	" Remove .git suffix if present
	let repo = substitute(repo, '\.git$', '', '')

	" Debug info
	echom "Parsed remote URL: " . remote_url
	echom "Owner: " . owner . " | Repo: " . repo

	return {'owner': owner, 'repo': repo}
endfunction

" Improved PR list function in autoload/gh_review.vim
function! gh_review#list_prs() abort
	try
		let token = gh_review#get_token()
		let repo_info = gh_review#get_repo_info()

		echom "Fetching PRs for " . repo_info.owner . "/" . repo_info.repo . "..."

		" Build the GitHub API URL
		let api_url = 'https://api.github.com/repos/' . repo_info.owner . '/' . repo_info.repo . '/pulls?state=open'

		" Use the improved API function
		let prs = gh_review#api#get_json(api_url)

		if empty(prs)
			echom "No open PRs found!"
			return
		endif

		" Create new buffer for PR list
		silent! execute 'new [GH-PR-List]'
		setlocal buftype=nofile bufhidden=wipe noswapfile nowrap
		setlocal filetype=gh_pr_list

		" Populate buffer with PR info in a cleaner format
		call setline(1, "# Open Pull Requests for " . repo_info.owner . "/" . repo_info.repo)
		call append(line('$'), "")
		call append(line('$'), "ID  | PR #    | Title                                            | Author       | Updated")
		call append(line('$'), "----|---------|-------------------------------------------------|--------------|--------")

		let idx = 1
		for pr in prs
			" Format the date to be more readable
			let updated_at = substitute(pr.updated_at, 'T', ' ', 'g')
			let updated_at = substitute(updated_at, 'Z', '', 'g')
			let updated_at = strpart(updated_at, 0, 16)  " Just show date and time, not seconds

			" Truncate long titles
			let title = pr.title
			if len(title) > 48
				let title = strpart(title, 0, 45) . '...'
			endif

			" Format the line with proper alignment
			let line = printf("%-3d | #%-6d | %-48s | %-12s | %s",
						\ idx,
						\ pr.number,
						\ title,
						\ pr.user.login,
						\ updated_at)

			call append(line('$'), line)
			let idx += 1
		endfor

		" Add mappings for the PR list buffer
		nnoremap <buffer> <CR> :call <SID>review_pr_under_cursor()<CR>

		" Store PR data for later use
		let b:gh_prs = prs

		" Move cursor to first PR
		normal! 5G

	catch
		echohl ErrorMsg
		echom v:exception
		echohl None
	endtry
endfunction

" Updated helper function to review PR under cursor
function! s:review_pr_under_cursor() abort
	if !exists('b:gh_prs')
		echohl ErrorMsg
		echom "PR data not available!"
		echohl None
		return
	endif

	let line_text = getline('.')
	let pr_idx_match = matchlist(line_text, '^\s*\(\d\+\)\s*|')

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
" Improved PR review function in autoload/gh_review.vim
function! gh_review#review(pr_number) abort
	try
		let token = gh_review#get_token()
		let repo_info = gh_review#get_repo_info()

		" Get PR details
		let endpoint = 'https://api.github.com/repos/' . repo_info.owner . '/' . repo_info.repo . '/pulls/' . a:pr_number
		let pr = gh_review#api#get_json(endpoint)

		" Get PR files
		let files_endpoint = endpoint . '/files'
		let pr_files = gh_review#api#get_json(files_endpoint)

		" Get PR diff
		let headers = {'Accept': 'application/vnd.github.v3.diff'}
		let diff = gh_review#api#request(endpoint, 'GET', headers, {})

		" Create new buffer for PR review
		silent! execute 'new [GH-PR-#' . a:pr_number . ']'
		setlocal buftype=nofile bufhidden=wipe noswapfile
		setlocal filetype=gh_pr

		" Store PR info
		let b:gh_pr = pr
		let b:gh_pr_number = a:pr_number
		let b:gh_repo_info = repo_info
		let b:gh_pr_files = pr_files

		" Add PR metadata at the top in a more structured format
		call setline(1, "# PR #" . a:pr_number . ": " . pr.title)
		call append(line('$'), "")
		call append(line('$'), "Author: " . pr.user.login)
		call append(line('$'), "Branch: " . pr.head.ref . " → " . pr.base.ref)
		call append(line('$'), "Created: " . substitute(pr.created_at, 'T', ' ', 'g'))
		call append(line('$'), "URL: " . pr.html_url)
		call append(line('$'), "")

		" Add PR description with proper formatting
		call append(line('$'), "## Description")
		call append(line('$'), "")
		if !empty(pr.body)
			for line in split(pr.body, '\n')
				call append(line('$'), line)
			endfor
		else
			call append(line('$'), "*No description provided*")
		endif
		call append(line('$'), "")

		" Add files section
		call append(line('$'), "## Files Changed (" . len(pr_files) . ")")
		call append(line('$'), "")
		let file_index = 1
		for file in pr_files
			let status = file.status
			let status_symbol = '•'
			if status == 'added'
				let status_symbol = '+'
			elseif status == 'removed'
				let status_symbol = '-'
			elseif status == 'modified'
				let status_symbol = 'M'
			elseif status == 'renamed'
				let status_symbol = '→'
			endif

			call append(line('$'), file_index . ". [" . status_symbol . "] " . file.filename . 
						\ " (" . file.changes . " changes: +" . file.additions . " -" . file.deletions . ")")
			let file_index += 1
		endfor
		call append(line('$'), "")

		" Add review controls section
		call append(line('$'), "## Review Controls")
		call append(line('$'), "")
		call append(line('$'), "- Press <leader>c to add a comment")
		call append(line('$'), "- Press <leader>a to approve the PR")
		call append(line('$'), "- Press <leader>r to request changes")
		call append(line('$'), "- Press <leader>m to merge the PR")
		call append(line('$'), "- Press <leader>f to open a specific file in the PR")
		call append(line('$'), "")

		" Add diff content with a header
		call append(line('$'), "## Diff")
		call append(line('$'), "")
		let diff_lines = split(diff, '\n')
		call append(line('$'), diff_lines)

		" Add mappings for the PR review buffer
		nnoremap <buffer> <leader>c :call gh_review#comment()<CR>
		nnoremap <buffer> <leader>a :call gh_review#approve(b:gh_pr_number)<CR>
		nnoremap <buffer> <leader>r :call gh_review#request_changes(b:gh_pr_number)<CR>
		nnoremap <buffer> <leader>m :call gh_review#merge(b:gh_pr_number)<CR>
		nnoremap <buffer> <leader>f :call <SID>open_pr_file()<CR>

		" Move cursor to the start of the PR description
		call search("^## Description")
		normal! j

	catch
		echohl ErrorMsg
		echom v:exception
		echohl None
	endtry
endfunction

" New function to open a specific file from the PR
function! s:open_pr_file() abort
	if !exists('b:gh_pr_files') || empty(b:gh_pr_files)
		echohl ErrorMsg
		echom "PR files information not available!"
		echohl None
		return
	endif

	" Create a numbered list of files
	let file_list = []
	let idx = 1
	for file in b:gh_pr_files
		call add(file_list, idx . ". " . file.filename)
		let idx += 1
	endfor

	" Display file list in a preview window
	silent! execute 'pedit PR-Files'
	wincmd P
	setlocal buftype=nofile bufhidden=wipe noswapfile
	call setline(1, "Select a file number to open:")
	call append(line('$'), "")
	call append(line('$'), file_list)
	wincmd p

	" Ask user to select a file
	echohl Question
	let file_idx = input('Enter file number to open: ')
	echohl None

	" Close preview window
	pclose

	" Validate and process input
	if empty(file_idx) || file_idx !~ '^\d\+$'
		echom "Invalid file number."
		return
	endif

	let file_idx = str2nr(file_idx) - 1
	if file_idx < 0 || file_idx >= len(b:gh_pr_files)
		echohl ErrorMsg
		echom "File number out of range."
		echohl None
		return
	endif

	let file = b:gh_pr_files[file_idx]

	" Get file content for both base and head versions
	let repo_info = b:gh_repo_info
	let pr = b:gh_pr

	" URL for base (original) version
	let base_content_endpoint = 'https://api.github.com/repos/' . repo_info.owner . '/' . repo_info.repo .
				\ '/contents/' . file.filename . '?ref=' . pr.base.sha

	" URL for head (changed) version
	let head_content_endpoint = 'https://api.github.com/repos/' . repo_info.owner . '/' . repo_info.repo .
				\ '/contents/' . file.filename . '?ref=' . pr.head.sha

	try
		" For added files, base version doesn't exist
		let base_content = ''
		if file.status != 'added'
			let base_response = gh_review#api#get_json(base_content_endpoint)
			if has_key(base_response, 'content')
				let base_content = system('echo ' . shellescape(base_response.content) . ' | base64 --decode')
			endif
		endif

		" For deleted files, head version doesn't exist
		let head_content = ''
		if file.status != 'removed'
			let head_response = gh_review#api#get_json(head_content_endpoint)
			if has_key(head_response, 'content')
				let head_content = system('echo ' . shellescape(head_response.content) . ' | base64 --decode')
			endif
		endif

		" Open file versions in split views
		silent! execute 'new [PR-' . pr.number . '-Base]-' . file.filename
		setlocal buftype=nofile bufhidden=wipe noswapfile
		if !empty(base_content)
			call setline(1, split(base_content, '\n'))
		else
			call setline(1, "[File does not exist in base version]")
		endif

		" Try to set filetype based on filename extension
		let ext = fnamemodify(file.filename, ':e')
		if !empty(ext)
			execute 'setlocal filetype=' . ext
		endif

		" Open head version in a vertical split
		silent! execute 'vnew [PR-' . pr.number . '-Head]-' . file.filename
		setlocal buftype=nofile bufhidden=wipe noswapfile
		if !empty(head_content)
			call setline(1, split(head_content, '\n'))
		else
			call setline(1, "[File does not exist in head version]")
		endif

		" Try to set filetype based on filename extension
		if !empty(ext)
			execute 'setlocal filetype=' . ext
		endif

		" Enable diff mode
		windo diffthis

	catch
		echohl ErrorMsg
		echom "Failed to fetch file content: " . v:exception
		echohl None
	endtry
endfunction

" Updated comment function in autoload/gh_review.vim
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

			" Use the improved API function
			let response = gh_review#api#post_json(endpoint, payload)

			" Display success message with link to the comment
			if has_key(response, 'html_url')
				echom "Comment posted successfully! View at: " . response.html_url
			else
				echom "Comment posted successfully!"
			endif
		else
			" General PR comment
			let payload = {'body': comment_text}
			let endpoint = 'https://api.github.com/repos/' . b:gh_repo_info.owner . '/' . b:gh_repo_info.repo .
						\ '/issues/' . b:gh_pr_number . '/comments'

			" Use the improved API function
			let response = gh_review#api#post_json(endpoint, payload)

			" Display success message with link to the comment
			if has_key(response, 'html_url')
				echom "Comment posted successfully! View at: " . response.html_url
			else
				echom "Comment posted successfully!"
			endif
		endif

	catch
		echohl ErrorMsg
		echom v:exception
		echohl None
	endtry
endfunction

" Updated review submission function
function! s:submit_review(pr_number, event) abort
	try
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

		let endpoint = 'https://api.github.com/repos/' . repo_info.owner . '/' . repo_info.repo .
					\ '/pulls/' . a:pr_number . '/reviews'

		" Use the improved API function
		let response = gh_review#api#post_json(endpoint, payload)

		" Display success message with HTML URL if available
		if has_key(response, 'html_url')
			echom "Review submitted successfully! View at: " . response.html_url
		else
			echom "Review submitted successfully!"
		endif

	catch
		echohl ErrorMsg
		echom v:exception
		echohl None
	endtry
endfunction

" Updated merge function
function! gh_review#merge(pr_number) abort
	try
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

		let endpoint = 'https://api.github.com/repos/' . repo_info.owner . '/' . repo_info.repo .
					\ '/pulls/' . a:pr_number . '/merge'

		" Use the improved API function
		let response = gh_review#api#put_json(endpoint, payload)

		" Display success message with commit SHA if available
		if has_key(response, 'sha')
			echom "PR #" . a:pr_number . " merged successfully! Commit SHA: " . response.sha
		else
			echom "PR #" . a:pr_number . " merged successfully!"
		endif

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

" Completion for merge strategies
function! gh_review#complete_merge_strategies(ArgLead, CmdLine, CursorPos) abort
	return filter(['merge', 'squash', 'rebase'], 'v:val =~ "^" . a:ArgLead')
endfunction

" refresh function to reload PR data
function! gh_review#refresh() abort
	" Check which buffer we're in
	let bufname = bufname('%')

	if bufname =~ '\[GH-PR-List\]'
		" We're in PR list buffer, refresh it
		call gh_review#list_prs()
		return
	endif

	if bufname =~ '\[GH-PR-#\d\+\]'
		" We're in PR review buffer, refresh it
		let pr_num_match = matchlist(bufname, '#\(\d\+\)')
		if !empty(pr_num_match)
			let pr_number = pr_num_match[1]
			call gh_review#review(pr_number)
			return
		endif
	endif

	echohl ErrorMsg
	echom "Not in a GitHub PR buffer!"
	echohl None
endfunction
