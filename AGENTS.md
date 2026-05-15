# Agent Workflows for Dotfiles Project

This document outlines the agent workflows and guidelines for this dotfiles repository.

## Overview

This document specifies how AI agents should interact with this dotfiles project for:
- Managing configurations
- Creating and managing GitHub issues and pull requests
- Running tests
- Deploying changes

## Core Workflow Principles

### 0. Create a Branch First

Before implementing any feature or change:

1. **Fetch latest main**
2. **Create a feature branch** with a descriptive name
3. **Work on the branch** - make all changes
4. **Run tests** - ensure they pass
5. **Push the branch** and create a PR

```bash
# Fetch latest main and create branch
git fetch origin main
git checkout -b feature/description-of-change

# Or use gh CLI
gh pr create --base main --head feature/description-of-change --title "..." --body "..."
```

### 1. Start with Creating the Job

When implementing a new feature or change:

1. **Create a GitHub issue** to propose the change
2. **Wait for approval** or discussion before implementing
3. **Document the scope** clearly before writing code

```bash
# Create a new issue
gh issue create --title "Feature: description" --body "Detailed description"
```

### 2. Use `gh` CLI First, Fall Back to GraphQL API

For all GitHub operations, prefer the `gh` CLI:

```bash
# Examples
gh issue list
gh pr create --title "..." --body "..."
gh pr comment 123 --body "Comment text"
```

If the `gh` CLI doesn't support an operation, use the GitHub GraphQL API:

```bash
# GraphQL API fallback example
gh api graphql -f query='query { ... }'
```

### 3. Testing Workflow

**Always build tests FIRST before implementing features.**

#### Testing Process:
1. **Design the test** - Define what needs to be tested
2. **Write the test** - Create test files or modify existing tests
3. **Run the test** - Verify it works correctly
4. **Ask for agreement** - Show the test plan to the user
5. **Implement the feature** - Only after test approval

#### Existing Test Infrastructure:

This project uses Docker-based smoke tests located at `tests/docker/`:

```bash
# Run smoke tests
docker build -f tests/docker/Dockerfile -t dotfiles-startup-test tests/docker
docker run --rm -v "$PWD:/workspace:ro" dotfiles-startup-test
```

#### New Test Guidelines:

For new features, tests should be:
- **Specific**: Test one thing clearly
- **Unambiguous**: Clear pass/fail criteria
- **Realistic**: Test actual use cases, not just edge cases

Example test addition to `tests/docker/startup_smoke.sh`:

```bash
step "testing new feature"
# Add specific test assertions here
assert_command "new-feature-command"
assert_file_resolves_to_path "$home/.config/new-feature" "$repo/.config/new-feature"
```

### 4. Pull Request Workflow

When a PR is ready:

1. **Push your branch** first
2. **Create the PR** from your feature branch with a clear title and description
3. **Reference the issue** if applicable
4. **Add comments** explaining complex changes
5. **Link tests** that verify the changes

```bash
# Push branch
git push -u origin feature/description-of-change

# Create PR
gh pr create \
  --title "feat: add new configuration feature" \
  --body "Closes #123\n\nDetailed description of changes."

# Add comment to PR
gh pr comment 456 --body "Testing instructions:\n1. Run docker build...\n2. Verify..."
```

### 5. Large PR Guidelines

If a PR is too large or complex:

1. **Assess the PR size** - If >500 lines or multiple concerns, consider splitting
2. **Ask the user**: "This PR is large. Should we split it into multiple PRs?"
3. **Split by logical units** - Each PR should have a single focus
4. **Maintain dependencies** - Ensure PRs can be merged in correct order

Example split:
- PR 1: Add test infrastructure
- PR 2: Implement feature with tests
- PR 3: Update documentation

## Repository-Specific Guidelines

### File Structure

| Path | Purpose |
|------|---------|
| `startup.sh` | Main installation script (POSIX sh) |
| `install.sh` | Enhanced installer with package management |
| `tests/docker/startup_smoke.sh` | Docker-based smoke tests |
| `.config/nvim/` | Neovim configuration |

### Configuration Management

- `~/.zsh_extra` - Machine-specific settings (NOT tracked)
- All tracked files are symlinked via `stow`
- Repository-only files: `README.md`, `startup.sh`, `install.sh`, `tests/`, etc.

### Neovim Configuration

- Based on NvChad
- Tests verify headless startup
- Check `lazy-lock.json` for plugin versions

## Quick Reference

### Common Commands

```bash
# Create branch from main
git fetch origin main
git checkout -b feature/description-of-change

# Or use gh CLI to create branch and PR
gh pr create --base main --head feature/description-of-change --title "..." --body "..."

# Create issue
gh issue create --title "..." --body "..."

# Create PR
gh pr create --title "..." --body "..."

# Add PR comment
gh pr comment <number> --body "..."

# Run tests
./tests/docker/startup_smoke.sh

# Dry run installation
./startup.sh --dry-run
```

### Testing Checklist

Before PR submission:

- [ ] Tests written and passing
- [ ] Docker smoke tests pass
- [ ] No breaking changes
- [ ] Documentation updated
- [ ] PR references issue (if applicable)
- [ ] Clear description of changes

## Agent Skills

This repository uses the following pi skills:

| Skill | Purpose |
|-------|---------|
| pi-processes | Manage background processes (dev servers, watchers) |
| commit | Git commit best practices |
| git-workflow | Branching, PRs, conflict resolution |
