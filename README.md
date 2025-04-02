# vim-gh-review

A Vim plugin for reviewing GitHub pull requests without leaving your editor.

## Features

- List open pull requests in the current repository
- View PR details and diffs
- Add comments to specific lines
- Approve or request changes on PRs
- Merge PRs with different strategies (merge, squash, rebase)

## Requirements

- Vim compiled with `+job` and `+json` features
- `curl` command-line tool
- A GitHub personal access token

## Installation

### Using vim-plug

```vim
Plug 'USKhokhar/vim-gh-review'
```

### Using Vundle

```vim
Plugin 'USKhokhar/vim-gh-review'
```

### Using Pathogen

```bash
git clone https://github.com/USKhokhar/vim-gh-review.git ~/.vim/bundle/vim-gh-review
```

## Setup

After installing the plugin, set up your GitHub token:

```vim
:GHSetupToken
```

You will be prompted to enter your GitHub personal access token. The token needs to have the following permissions:
- `repo` scope for private repositories
- `public_repo` scope for public repositories

## Usage

### Commands

- `:GHListPRs` - List all open pull requests for the current repository
- `:GHReview <pr_number>` - Open a specific pull request for review
- `:GHComment [line_number]` - Add a comment to the current PR
- `:GHApprove <pr_number>` - Approve the specified pull request
- `:GHRequestChanges <pr_number>` - Request changes for the specified pull request
- `:GHMerge <pr_number>` - Merge the specified pull request

### Mappings

In PR list buffer:
- `<CR>` - Open the PR under cursor for review

In PR review buffer:
- `<leader>c` - Add comment at current position
- `<leader>a` - Approve the PR
- `<leader>r` - Request changes for the PR
- `<leader>m` - Merge the PR

## Configuration

```vim
" Path to store your GitHub token
let g:gh_review_token_file = '~/.config/gh_review_token'

" Directory to store cached PR data
let g:gh_review_cache_dir = '~/.cache/gh_review'
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

Distributed under the same terms as Vim itself. See `:help license`.


## Test PRs 
- Test PR#1 with reamde edits 
