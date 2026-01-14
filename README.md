# dev-scripts

Personal development scripts and workflow enhancement tools.

## Scripts

### git-worktree-manager.sh

Interactive script to manage git worktrees across multiple repositories.

#### Features

- Create worktree from existing branch
- Create worktree with new branch (with automatic branch name sanitization)
- Delete worktrees
- List all worktrees
- Fetch all branches for a repo
- Supports `fzf` for enhanced interactive selection (falls back to basic menu if not installed)

#### Branch Name Sanitization

When creating new branches, names are automatically sanitized to git-accepted format:

- Spaces replaced with `-`
- Invalid characters removed (`~`, `^`, `:`, `?`, `*`, `[`, `\`, `@{`)
- Consecutive `..` collapsed to `.`
- Consecutive `-` and `/` collapsed
- Leading/trailing `-`, `/`, `.` removed
- `.lock` suffix removed

#### Installation

```bash
# Clone the repository
git clone https://github.com/divakarmanoj/dev-scripts.git

# Make the script executable (if not already)
chmod +x dev-scripts/git-worktree-manager.sh

# Optionally, add to your PATH or create an alias
alias gwm="~/path/to/dev-scripts/git-worktree-manager.sh"
```

#### Configuration

Edit the `OFFICE_DIR` variable at the top of the script to point to your repositories directory:

```bash
OFFICE_DIR="${HOME}/dev/office"
```

#### Usage

```bash
./git-worktree-manager.sh
```

#### Dependencies

- `git`
- `fzf` (optional, for better interactive experience)
