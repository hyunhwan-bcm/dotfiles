dotfiles updater
=================

This repo provides a convenient shell function to check for remote updates in `$HOME/dotfiles` and optionally pull them.

Usage
-----

- Run the check and prompt: `df-check` or `df-update`
- The function will:
  - verify `$HOME/dotfiles` is a Git repository
  - fetch updates from the remote
  - show commits that are on the remote but not on the local branch
  - ask for confirmation before pulling

Notes
-----
- If your local branch has diverged from the remote, the function will not auto-pull; it shows guidance to handle the divergence manually.
- If you have uncommitted changes in the repo, the function will refuse to auto-pull and advise you to stash or commit changes first.

