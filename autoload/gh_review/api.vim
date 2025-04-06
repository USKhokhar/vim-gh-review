" Improved API request function in autoload/gh_review/api.vim
function! gh_review#api#request(endpoint, method, headers, data) abort
	let token = gh_review#get_token()
	let cmd = ['curl', '-s', '-X', a:method, '-i']  " Add -i to include response headers

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
		let data_json = json_encode(a:data)
		call add(cmd, '-d')
		call add(cmd, shellescape(data_json))

		" Debug output
		echom "Sending data: " . data_json
	endif

	" Add endpoint URL
	call add(cmd, a:endpoint)

	" Debug output
	echom "Making API request: " . join(cmd, ' ')

	let result = system(join(cmd, ' '))

	" Check HTTP status code in response headers
	let headers_and_body = split(result, '\r\n\r\n', 1)
	let headers = headers_and_body[0]
	let status_match = matchlist(headers, '^HTTP/[0-9.]\+ \([0-9]\+\)')

	if !empty(status_match)
		let status_code = str2nr(status_match[1])
		if status_code < 200 || status_code >= 300
			throw "API request failed with status " . status_code . ": " . headers
		endif
	endif

	if v:shell_error != 0
		throw "API request failed: " . result
	endif

	" Return just the body part if we have both headers and body
	if len(headers_and_body) > 1
		return headers_and_body[1]
	endif

	return result
endfunction

" Improved JSON handling functions
function! gh_review#api#get_json(endpoint, headers = {}) abort
	let headers = extend({'Accept': 'application/json'}, a:headers)
	let result = gh_review#api#request(a:endpoint, 'GET', headers, {})

	try
		return json_decode(result)
	catch
		echohl ErrorMsg
		echom "Failed to parse API response as JSON: " . result
		echohl None
		throw "JSON parse error"
	endtry
endfunction

function! gh_review#api#post_json(endpoint, data, headers = {}) abort
	let headers = extend({'Content-Type': 'application/json', 'Accept': 'application/json'}, a:headers)
	let result = gh_review#api#request(a:endpoint, 'POST', headers, a:data)

	try
		let response = json_decode(result)
		echom "API response: " . json_encode(response)
		return response
	catch
		echohl ErrorMsg
		echom "Failed to parse API response as JSON: " . result
		echohl None
		throw "JSON parse error"
	endtry
endfunction

function! gh_review#api#put_json(endpoint, data, headers = {}) abort
	let headers = extend({'Content-Type': 'application/json', 'Accept': 'application/json'}, a:headers)
	let result = gh_review#api#request(a:endpoint, 'PUT', headers, a:data)

	try
		let response = json_decode(result)
		echom "API response: " . json_encode(response)
		return response
	catch
		echohl ErrorMsg
		echom "Failed to parse API response as JSON: " . result
		echohl None
		throw "JSON parse error"
	endtry
endfunction
