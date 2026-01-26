#!/bin/bash

# Git Worktree Manager
# Interactive script to manage git worktrees across multiple repositories

OFFICE_DIR="${HOME}/dev/office"
WORKTREE_SUFFIX="-wr-"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if fzf is available for better interactive experience
HAS_FZF=$(command -v fzf &> /dev/null && echo "true" || echo "false")

# Sanitize branch name to match git-accepted format (similar to VS Code)
sanitize_branch_name() {
    local name="$1"

    # Trim leading/trailing whitespace
    name=$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Replace spaces with hyphens
    name=$(echo "$name" | tr ' ' '-')

    # Remove invalid git ref characters: ~ ^ : ? * [ \ and @{
    name=$(echo "$name" | sed 's/[~^:?*\[\\]//g' | sed 's/@{//g')

    # Replace consecutive dots with single dot (.. is invalid)
    name=$(echo "$name" | sed 's/\.\.\.*/./g')

    # Collapse consecutive hyphens into single hyphen
    name=$(echo "$name" | sed 's/--*/-/g')

    # Collapse consecutive slashes into single slash
    name=$(echo "$name" | sed 's|//*|/|g')

    # Remove leading/trailing hyphens, slashes, and dots
    name=$(echo "$name" | sed 's/^[-/.]*//;s/[-/.]*$//')

    # Remove .lock suffix if present (reserved by git)
    name=$(echo "$name" | sed 's/\.lock$//')

    echo "$name"
}

print_header() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}    Git Worktree Manager${NC}"
    echo -e "${CYAN}========================================${NC}\n"
}

print_menu() {
    echo -e "${YELLOW}Select an action:${NC}"
    echo "  1) Create worktree from existing branch"
    echo "  2) Create worktree with new branch"
    echo "  3) Delete worktree"
    echo "  4) List all worktrees"
    echo "  5) Fetch all branches for a repo"
    echo "  6) Refresh all repos (pull main/master)"
    echo "  7) Exit"
    echo ""
}

# Interactive menu selection with fzf
select_menu_action() {
    local actions=(
        "Create worktree from existing branch"
        "Create worktree with new branch"
        "Delete worktree"
        "List all worktrees"
        "Fetch all branches for a repo"
        "Refresh all repos (pull main/master)"
        "Exit"
    )

    if [ "$HAS_FZF" = "true" ]; then
        selected=$(printf '%s\n' "${actions[@]}" | fzf --height=40% --reverse --prompt="Action: " --header="Use arrow keys, Enter to select")
        case "$selected" in
            "Create worktree from existing branch") echo "1" ;;
            "Create worktree with new branch") echo "2" ;;
            "Delete worktree") echo "3" ;;
            "List all worktrees") echo "4" ;;
            "Fetch all branches for a repo") echo "5" ;;
            "Refresh all repos (pull main/master)") echo "6" ;;
            "Exit") echo "7" ;;
            *) echo "" ;;
        esac
    else
        print_menu
        read -p "Enter choice (1-7): " choice
        echo "$choice"
    fi
}

# Get all git repositories sorted by creation time (oldest first based on .git creation)
get_repos() {
    local repos=()
    for dir in "${OFFICE_DIR}"/*/; do
        if [ -d "${dir}.git" ]; then
            repos+=("$dir")
        fi
    done

    # Sort by .git directory modification time (most recent first)
    for repo in "${repos[@]}"; do
        stat -f "%m %N" "${repo}.git" 2>/dev/null || stat -c "%Y %n" "${repo}.git" 2>/dev/null
    done | sort -rn | cut -d' ' -f2- | while read -r git_dir; do
        dirname "$git_dir" | xargs basename
    done
}

# Interactive repo selection
select_repo() {
    local prompt="${1:-Select a repository}"
    local repos=($(get_repos))

    if [ ${#repos[@]} -eq 0 ]; then
        echo -e "${RED}No git repositories found in ${OFFICE_DIR}${NC}"
        return 1
    fi

    if [ "$HAS_FZF" = "true" ]; then
        # Use fzf for interactive selection with search
        selected=$(printf '%s\n' "${repos[@]}" | fzf --height=40% --reverse --prompt="$prompt: " --header="Type to search, Enter to select")
    else
        # Fallback to basic selection with search
        echo -e "${YELLOW}$prompt${NC}"
        echo -e "${BLUE}(Type prefix to filter or press Enter to see all)${NC}"
        read -p "Search: " search_term

        local filtered=()
        for repo in "${repos[@]}"; do
            if [ -z "$search_term" ] || [[ "$repo" == *"$search_term"* ]]; then
                filtered+=("$repo")
            fi
        done

        if [ ${#filtered[@]} -eq 0 ]; then
            echo -e "${RED}No repos match '$search_term'${NC}"
            return 1
        fi

        echo -e "\n${YELLOW}Available repositories:${NC}"
        local i=1
        for repo in "${filtered[@]}"; do
            echo "  $i) $repo"
            ((i++))
        done
        echo ""

        read -p "Enter number (1-${#filtered[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#filtered[@]} ]; then
            selected="${filtered[$((choice-1))]}"
        else
            echo -e "${RED}Invalid selection${NC}"
            return 1
        fi
    fi

    if [ -z "$selected" ]; then
        return 1
    fi

    echo "$selected"
}

# Get branches for a repo (includes remote branches)
get_branches() {
    local repo_path="${OFFICE_DIR}/$1"
    cd "$repo_path" || return 1

    # Get all branches (local and remote)
    git branch -a --format='%(refname:short)' 2>/dev/null | sed 's|origin/||' | sort -u | grep -v "^HEAD$"
}

# Select a branch
select_branch() {
    local repo="$1"
    local prompt="${2:-Select a branch}"
    local branches=($(get_branches "$repo"))

    if [ ${#branches[@]} -eq 0 ]; then
        echo -e "${RED}No branches found${NC}"
        return 1
    fi

    if [ "$HAS_FZF" = "true" ]; then
        selected=$(printf '%s\n' "${branches[@]}" | fzf --height=40% --reverse --prompt="$prompt: " --header="Type to search, Enter to select")
    else
        echo -e "${YELLOW}$prompt${NC}"
        read -p "Search (or Enter for all): " search_term

        local filtered=()
        for branch in "${branches[@]}"; do
            if [ -z "$search_term" ] || [[ "$branch" == *"$search_term"* ]]; then
                filtered+=("$branch")
            fi
        done

        if [ ${#filtered[@]} -eq 0 ]; then
            echo -e "${RED}No branches match '$search_term'${NC}"
            return 1
        fi

        echo -e "\n${YELLOW}Available branches:${NC}"
        local i=1
        for branch in "${filtered[@]}"; do
            echo "  $i) $branch"
            ((i++))
        done
        echo ""

        read -p "Enter number (1-${#filtered[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#filtered[@]} ]; then
            selected="${filtered[$((choice-1))]}"
        else
            echo -e "${RED}Invalid selection${NC}"
            return 1
        fi
    fi

    if [ -z "$selected" ]; then
        return 1
    fi

    echo "$selected"
}

# Fetch all branches for a repo
fetch_branches() {
    local repo="$1"
    local repo_path="${OFFICE_DIR}/$repo"

    echo -e "${BLUE}Fetching all branches for ${repo}...${NC}"
    cd "$repo_path" || return 1

    git fetch --all --prune

    echo -e "${GREEN}Done! Available branches:${NC}"
    git branch -a --format='%(refname:short)' | head -20

    local total=$(git branch -a | wc -l | tr -d ' ')
    if [ "$total" -gt 20 ]; then
        echo -e "${YELLOW}... and $((total - 20)) more branches${NC}"
    fi
}

# Refresh all repos by pulling main/master branch
refresh_all_repos() {
    echo -e "${YELLOW}Refreshing all repositories...${NC}\n"

    local repos=($(get_repos))
    local success_count=0
    local fail_count=0
    local skipped_count=0

    for repo in "${repos[@]}"; do
        local repo_path="${OFFICE_DIR}/$repo"
        cd "$repo_path" || continue

        # Determine the default branch (main or master)
        local default_branch=""
        if git show-ref --verify --quiet refs/remotes/origin/main; then
            default_branch="main"
        elif git show-ref --verify --quiet refs/remotes/origin/master; then
            default_branch="master"
        else
            echo -e "${YELLOW}[SKIP]${NC} $repo - no main/master branch found"
            ((skipped_count++))
            continue
        fi

        # Check if we're on the default branch and it's clean
        local current_branch=$(git branch --show-current 2>/dev/null)

        if [ "$current_branch" = "$default_branch" ]; then
            # Check for uncommitted changes
            if ! git diff --quiet || ! git diff --cached --quiet; then
                echo -e "${YELLOW}[SKIP]${NC} $repo - uncommitted changes on $default_branch"
                ((skipped_count++))
                continue
            fi

            echo -e "${BLUE}[PULL]${NC} $repo ($default_branch)..."
            if git pull --ff-only origin "$default_branch" 2>/dev/null; then
                echo -e "${GREEN}[OK]${NC}   $repo - updated $default_branch"
                ((success_count++))
            else
                echo -e "${RED}[FAIL]${NC} $repo - pull failed"
                ((fail_count++))
            fi
        else
            # Not on default branch, just fetch
            echo -e "${BLUE}[FETCH]${NC} $repo (on $current_branch, fetching $default_branch)..."
            if git fetch origin "$default_branch" 2>/dev/null; then
                echo -e "${GREEN}[OK]${NC}   $repo - fetched $default_branch"
                ((success_count++))
            else
                echo -e "${RED}[FAIL]${NC} $repo - fetch failed"
                ((fail_count++))
            fi
        fi
    done

    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${GREEN}Success: $success_count${NC} | ${RED}Failed: $fail_count${NC} | ${YELLOW}Skipped: $skipped_count${NC}"
    echo -e "${CYAN}========================================${NC}"
}

# Create worktree from existing branch
create_worktree_existing() {
    local repo=$(select_repo "Select repository for worktree")
    [ -z "$repo" ] && return 1

    local repo_path="${OFFICE_DIR}/$repo"

    echo -e "${BLUE}Fetching latest branches...${NC}"
    cd "$repo_path" && git fetch --all --prune

    local branch=$(select_branch "$repo" "Select branch for worktree")
    [ -z "$branch" ] && return 1

    # Sanitize branch name for directory (replace / with -)
    local safe_branch=$(echo "$branch" | tr '/' '-')
    local worktree_name="${repo}${WORKTREE_SUFFIX}${safe_branch}"
    local worktree_path="${OFFICE_DIR}/${worktree_name}"

    if [ -d "$worktree_path" ]; then
        echo -e "${RED}Worktree already exists at: ${worktree_path}${NC}"
        return 1
    fi

    echo -e "${BLUE}Creating worktree...${NC}"
    cd "$repo_path" || return 1

    # Always create worktree from origin to ensure we have the latest remote version
    # Delete local branch if it exists so we can recreate it from origin
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        git branch -D "$branch" 2>/dev/null
    fi
    git worktree add "$worktree_path" -b "$branch" "origin/$branch"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Worktree created successfully!${NC}"
        echo -e "${GREEN}Location: ${worktree_path}${NC}"
    else
        echo -e "${RED}Failed to create worktree${NC}"
        return 1
    fi
}

# Create worktree with new branch
create_worktree_new_branch() {
    local repo=$(select_repo "Select repository for new branch")
    [ -z "$repo" ] && return 1

    local repo_path="${OFFICE_DIR}/$repo"

    echo -e "${BLUE}Fetching latest branches...${NC}"
    cd "$repo_path" && git fetch --all --prune

    # Select base branch
    echo -e "\n${YELLOW}Select the base branch to create new branch from:${NC}"
    local base_branch=$(select_branch "$repo" "Select base branch")
    [ -z "$base_branch" ] && return 1

    # Get new branch name
    echo ""
    read -p "Enter new branch name: " new_branch

    if [ -z "$new_branch" ]; then
        echo -e "${RED}Branch name cannot be empty${NC}"
        return 1
    fi

    # Sanitize the branch name to git-accepted format
    local sanitized_branch=$(sanitize_branch_name "$new_branch")

    if [ -z "$sanitized_branch" ]; then
        echo -e "${RED}Branch name is invalid after sanitization${NC}"
        return 1
    fi

    if [ "$new_branch" != "$sanitized_branch" ]; then
        echo -e "${YELLOW}Branch name sanitized: '${new_branch}' -> '${sanitized_branch}'${NC}"
        new_branch="$sanitized_branch"
    fi

    # Sanitize branch name for directory
    local safe_branch=$(echo "$new_branch" | tr '/' '-')
    local worktree_name="${repo}${WORKTREE_SUFFIX}${safe_branch}"
    local worktree_path="${OFFICE_DIR}/${worktree_name}"

    if [ -d "$worktree_path" ]; then
        echo -e "${RED}Worktree already exists at: ${worktree_path}${NC}"
        return 1
    fi

    echo -e "${BLUE}Creating worktree with new branch...${NC}"
    cd "$repo_path" || return 1

    # Always create worktree from origin to ensure we have the latest remote version
    git worktree add -b "$new_branch" "$worktree_path" "origin/$base_branch"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Worktree created successfully with new branch '${new_branch}'!${NC}"
        echo -e "${GREEN}Location: ${worktree_path}${NC}"
    else
        echo -e "${RED}Failed to create worktree${NC}"
        return 1
    fi
}

# List all worktrees
list_worktrees() {
    echo -e "${YELLOW}Current worktrees in ${OFFICE_DIR}:${NC}\n"

    local found=false
    for dir in "${OFFICE_DIR}"/*/; do
        if [ -d "${dir}.git" ]; then
            local repo_name=$(basename "$dir")
            local worktrees=$(cd "$dir" && git worktree list 2>/dev/null)

            if [ -n "$worktrees" ] && [ $(echo "$worktrees" | wc -l) -gt 1 ]; then
                echo -e "${CYAN}$repo_name:${NC}"
                echo "$worktrees" | while read -r line; do
                    echo "  $line"
                done
                echo ""
                found=true
            fi
        fi
    done

    # Also list standalone worktree directories
    echo -e "${YELLOW}Worktree directories:${NC}"
    for dir in "${OFFICE_DIR}"/*${WORKTREE_SUFFIX}*/; do
        if [ -d "$dir" ]; then
            echo "  $(basename "$dir")"
            found=true
        fi
    done 2>/dev/null

    if [ "$found" = false ]; then
        echo -e "${BLUE}No worktrees found${NC}"
    fi
}

# Delete worktree
delete_worktree() {
    # Find all worktree directories
    local worktrees=()
    for dir in "${OFFICE_DIR}"/*${WORKTREE_SUFFIX}*/; do
        if [ -d "$dir" ]; then
            worktrees+=("$(basename "$dir")")
        fi
    done 2>/dev/null

    if [ ${#worktrees[@]} -eq 0 ]; then
        echo -e "${YELLOW}No worktrees found to delete${NC}"
        return 0
    fi

    local selected
    if [ "$HAS_FZF" = "true" ]; then
        selected=$(printf '%s\n' "${worktrees[@]}" | fzf --height=40% --reverse --prompt="Select worktree to delete: " --header="Type to search, Enter to select")
    else
        echo -e "${YELLOW}Select worktree to delete:${NC}"
        local i=1
        for wt in "${worktrees[@]}"; do
            echo "  $i) $wt"
            ((i++))
        done
        echo ""

        read -p "Enter number (1-${#worktrees[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#worktrees[@]} ]; then
            selected="${worktrees[$((choice-1))]}"
        else
            echo -e "${RED}Invalid selection${NC}"
            return 1
        fi
    fi

    [ -z "$selected" ] && return 1

    local worktree_path="${OFFICE_DIR}/${selected}"

    # Extract repo name from worktree name
    local repo_name=$(echo "$selected" | sed "s/${WORKTREE_SUFFIX}.*//")
    local repo_path="${OFFICE_DIR}/${repo_name}"

    local confirm
    if [ "$HAS_FZF" = "true" ]; then
        confirm=$(printf 'No\nYes' | fzf --height=20% --reverse --prompt="Delete '${selected}'? " --header="Select Yes to confirm deletion")
    else
        echo -e "${YELLOW}Are you sure you want to delete worktree '${selected}'? (y/N)${NC}"
        read -p "" confirm_input
        [[ "$confirm_input" =~ ^[Yy]$ ]] && confirm="Yes" || confirm="No"
    fi

    if [ "$confirm" = "Yes" ]; then
        echo -e "${BLUE}Removing worktree...${NC}"

        # Remove from git worktree list
        if [ -d "$repo_path/.git" ]; then
            cd "$repo_path" && git worktree remove "$worktree_path" --force 2>/dev/null
        fi

        # If directory still exists, remove it
        if [ -d "$worktree_path" ]; then
            rm -rf "$worktree_path"
        fi

        echo -e "${GREEN}Worktree deleted successfully${NC}"
    else
        echo -e "${BLUE}Cancelled${NC}"
    fi
}

# Main menu loop
main() {
    print_header

    while true; do
        choice=$(select_menu_action)
        echo ""

        case $choice in
            1)
                create_worktree_existing
                ;;
            2)
                create_worktree_new_branch
                ;;
            3)
                delete_worktree
                ;;
            4)
                list_worktrees
                ;;
            5)
                local repo=$(select_repo "Select repository to fetch")
                [ -n "$repo" ] && fetch_branches "$repo"
                ;;
            6)
                refresh_all_repos
                ;;
            7)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            "")
                # User pressed Escape or cancelled
                continue
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                ;;
        esac

    done
}

# Run main function
main
