" Function to make an API request to GitHub
function! gh_review#api#request(endpoint, method, headers, data) abort
	let token = gh_review#get_token()
	let cmd = ['curl', '-s', '-X', a:method]

	" Add authorization header
	call add(cmd, '-H')
	call add(cmd, 'Authorization: token ' . token)

	" Add additional headers
	for [key, value] in items(a:headers)
		call add(cmd, '-H')
		call add(cmd, key . ': ' . value)
	endfor

	" Add data if provided
	if !empty(a:data)
		call add(cmd, '-d')
		call add(cmd, shellescape(json_encode(a:data)))
	endif

	" Add endpoint URL
	call add(cmd, a:endpoint)

	let result = system(join(cmd, ' '))

	if v:shell_error != 0
		throw "API request failed: " . result
	endif

	return result
endfunction

" Function to get API response as JSON
function! gh_review#api#get_json(endpoint, headers = {}) abort
	let headers = extend({'Accept': 'application/json'}, a:headers)
	let result = gh_review#api#request(a:endpoint, 'GET', headers, {})

	try
		return json_decode(result)
	catch
		throw "Failed to parse API response as JSON: " . result
	endtry
endfunction

" Function to post data to API
function! gh_review#api#post_json(endpoint, data, headers = {}) abort
	let headers = extend({'Content-Type': 'application/json', 'Accept': 'application/json'}, a:headers)
	let result = gh_review#api#request(a:endpoint, 'POST', headers, a:data)

	try
		return json_decode(result)
	catch
		throw "Failed to parse API response as JSON: " . result
	endtry
endfunction

" Function to put data to API
function! gh_review#api#put_json(endpoint, data, headers = {}) abort
	let headers = extend({'Content-Type': 'application/json', 'Accept': 'application/json'}, a:headers)
	let result = gh_review#api#request(a:endpoint, 'PUT', headers, a:data)

	try
		return json_decode(result)
	catch
		throw "Failed to parse API response as JSON: " . result
	endtry
endfunction
