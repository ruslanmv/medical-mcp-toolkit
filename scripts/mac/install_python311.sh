#!/bin/bash

# Python Installation Script for macOS
# Compatible with watsonx Orchestrate ADK (supports Python 3.11-3.13)
# NOTE: This script installs and configures Python only. No project/venv setup.

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    printf "${1}${2}${NC}\n"
}

# Function to print header
print_header() {
    echo
    print_color $BLUE "=============================================="
    print_color $BLUE "$1"
    print_color $BLUE "=============================================="
    echo
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect macOS architecture
detect_arch() {
    if [[ $(uname -m) == "arm64" ]]; then
        echo "Apple Silicon (M1/M2/M3)"
    else
        echo "Intel"
    fi
}

# Function to detect shell
detect_shell() {
    if [[ -n "$ZSH_VERSION" ]]; then
        echo "zsh"
    elif [[ -n "$BASH_VERSION" ]]; then
        echo "bash"
    else
        echo "unknown"
    fi
}

# Function to get shell config file
get_shell_config() {
    local shell_type
    shell_type=$(detect_shell)
    case $shell_type in
        "zsh")  echo "$HOME/.zshrc" ;;
        "bash") echo "$HOME/.bash_profile" ;;
        *)      echo "$HOME/.profile" ;;
    esac
}

# Function to check if Homebrew is installed
check_homebrew() {
    if ! command_exists brew; then
        print_color $YELLOW "Homebrew is not installed. Installing Homebrew first..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        # Add Homebrew to PATH for current session
        if [[ $(uname -m) == "arm64" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        else
            eval "$(/usr/local/bin/brew shellenv)"
        fi

        # Add to shell config
        local shell_config
        shell_config=$(get_shell_config)
        if [[ $(uname -m) == "arm64" ]]; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$shell_config"
        else
            echo 'eval "$(/usr/local/bin/brew shellenv)"' >> "$shell_config"
        fi

        print_color $GREEN "✓ Homebrew installed successfully"
    else
        print_color $GREEN "✓ Homebrew is already installed"
    fi
}

# Function to get current Python version
get_current_python_version() {
    if command_exists python3; then
        python3 --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "unknown"
    else
        echo "not installed"
    fi
}

# Function to check if Python version is installed via Homebrew
check_python_installed() {
    local version=$1
    brew list "python@$version" >/dev/null 2>&1
}

# Function to install Python version
install_python() {
    local version=$1
    print_header "Installing Python $version"

    # Check if already installed
    if check_python_installed "$version"; then
        print_color $YELLOW "Python $version is already installed via Homebrew!"
        read -p "Do you want to reinstall it? (y/N): " reinstall
        if [[ ! $reinstall =~ ^[Yy]$ ]]; then
            setup_python_links "$version"
            return 0
        fi

        print_color $BLUE "Uninstalling existing Python $version..."
        brew uninstall "python@$version" || true
    fi

    print_color $BLUE "Installing Python $version via Homebrew..."
    brew install "python@$version"

    print_color $GREEN "✓ Python $version installed successfully!"
    setup_python_links "$version"
}

# Function to setup Python links and PATH
setup_python_links() {
    local version=$1
    print_header "Setting up Python $version as default"

    # Get Homebrew prefix
    local brew_prefix
    if [[ $(uname -m) == "arm64" ]]; then
        brew_prefix="/opt/homebrew"
    else
        brew_prefix="/usr/local"
    fi

    local python_path="$brew_prefix/opt/python@$version/bin"
    local shell_config
    shell_config=$(get_shell_config)

    print_color $BLUE "Setting up symbolic links..."

    # Create symbolic links in Homebrew bin
    if [[ -f "$python_path/python$version" ]]; then
        ln -sf "$python_path/python$version" "$brew_prefix/bin/python3" 2>/dev/null || true
        ln -sf "$python_path/python$version" "$brew_prefix/bin/python"  2>/dev/null || true
    fi

    if [[ -f "$python_path/pip$version" ]]; then
        ln -sf "$python_path/pip$version" "$brew_prefix/bin/pip3" 2>/dev/null || true
        ln -sf "$python_path/pip$version" "$brew_prefix/bin/pip"  2>/dev/null || true
    fi

    print_color $BLUE "Updating PATH in $shell_config..."

    # Remove any existing Python PATH entries (backup first)
    if [[ -f "$shell_config" ]]; then
        cp "$shell_config" "$shell_config.backup.$(date +%Y%m%d_%H%M%S)"
        grep -v "python@" "$shell_config" > "$shell_config.tmp" && mv "$shell_config.tmp" "$shell_config"
    fi

    # Add new PATH entry
    {
      echo ""
      echo "# Python $version PATH (added by Python installer script)"
      echo "export PATH=\"$python_path:\$PATH\""
      # Ensure brew shellenv is present
      if ! grep -q "brew shellenv" "$shell_config" 2>/dev/null; then
        echo ""
        echo "# Homebrew PATH"
        if [[ $(uname -m) == "arm64" ]]; then
          echo 'eval "$(/opt/homebrew/bin/brew shellenv)"'
        else
          echo 'eval "$(/usr/local/bin/brew shellenv)"'
        fi
      fi
    } >> "$shell_config"

    # Update current session PATH
    export PATH="$python_path:$PATH"

    print_color $GREEN "✓ Python $version is now set as default!"
    print_color $PURPLE "Current Python setup:"
    print_color $PURPLE "- Python path: $python_path"
    print_color $PURPLE "- Shell config: $shell_config"
    print_color $PURPLE "- Architecture: $(detect_arch)"
}

# Function to verify installation
verify_installation() {
    print_header "Verifying Python Installation"

    echo "Checking Python..."
    if command_exists python3; then
        local python_version python_path
        python_version=$(python3 --version)
        python_path=$(which python3)
        print_color $GREEN "✓ Python3: $python_version"
        print_color $GREEN "✓ Location: $python_path"
    else
        print_color $RED "✗ Python3 not found"
        return 1
    fi

    if command_exists python; then
        local python_version python_path
        python_version=$(python --version)
        python_path=$(which python)
        print_color $GREEN "✓ Python: $python_version"
        print_color $GREEN "✓ Location: $python_path"
    else
        print_color $YELLOW "⚠ 'python' command not available (only 'python3')"
    fi

    echo "Checking pip..."
    if command_exists pip3; then
        local pip_version pip_path
        pip_version=$(pip3 --version)
        pip_path=$(which pip3)
        print_color $GREEN "✓ pip3: $pip_version"
        print_color $GREEN "✓ Location: $pip_path"
    else
        print_color $RED "✗ pip3 not found"
        return 1
    fi

    if command_exists pip; then
        local pip_version pip_path
        pip_version=$(pip --version)
        pip_path=$(which pip)
        print_color $GREEN "✓ pip: $pip_version"
        print_color $GREEN "✓ Location: $pip_path"
    else
        print_color $YELLOW "⚠ 'pip' command not available (only 'pip3')"
    fi

    echo "Testing Python functionality..."
    if python3 -c "import sys; print(f'Python {sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')" >/dev/null 2>&1; then
        local python_info
        python_info=$(python3 -c "import sys; print(f'Python {sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')")
        print_color $GREEN "✓ $python_info is working correctly"
    else
        print_color $RED "✗ Python is not working correctly"
        return 1
    fi

    # Check if it's in the supported range (3.11–3.13)
    local short_ver
    short_ver=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || echo "unknown")
    if [[ "$short_ver" == "3.11" || "$short_ver" == "3.12" || "$short_ver" == "3.13" ]]; then
        print_color $GREEN "✓ Python $short_ver is in the supported range (3.11–3.13)"
    else
        print_color $YELLOW "⚠ Python $short_ver is outside the recommended range (3.11–3.13)"
    fi

    print_color $GREEN "🎉 Python installation verification completed successfully!"
}

# Function to show post-installation instructions (no environment setup)
show_post_install() {
    print_header "Post-Installation Instructions"

    local shell_config
    shell_config=$(get_shell_config)

    print_color $PURPLE "Your Python setup is complete."
    echo
    print_color $BLUE "Important: Restart your terminal or run:"
    print_color $YELLOW "source $shell_config"
    echo
    print_color $BLUE "Next steps:"
    print_color $BLUE "1) Verify Python:    python3 --version"
    print_color $BLUE "2) Verify pip:       pip3 --version"
    print_color $BLUE "3) (Optional) Create a virtual environment in your project when needed:"
    print_color $YELLOW "   python3 -m venv .venv && source .venv/bin/activate"
}

# Function to show current Python status
show_python_status() {
    print_header "Current Python Status"

    print_color $BLUE "System Information:"
    print_color $BLUE "- macOS: $(sw_vers -productVersion)"
    print_color $BLUE "- Architecture: $(detect_arch)"
    print_color $BLUE "- Shell: $(detect_shell)"
    print_color $BLUE "- Shell config: $(get_shell_config)"
    echo

    print_color $BLUE "Python Status:"
    if command_exists python3; then
        local current_version current_path
        current_version=$(get_current_python_version)
        current_path=$(which python3)
        print_color $GREEN "✓ Current Python3: $current_version"
        print_color $GREEN "  Location: $current_path"
    else
        print_color $RED "✗ No Python3 found"
    fi

    if command_exists python; then
        local python_version python_path
        python_version=$(python --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "unknown")
        python_path=$(which python)
        print_color $GREEN "✓ Python: $python_version"
        print_color $GREEN "  Location: $python_path"
    else
        print_color $YELLOW "⚠ 'python' command not available"
    fi

    echo
    print_color $BLUE "Available Python versions via Homebrew:"
    for version in 3.11 3.12 3.13; do
        if check_python_installed "$version"; then
            print_color $GREEN "✓ Python $version (installed)"
        else
            print_color $YELLOW "○ Python $version (not installed)"
        fi
    done

    echo
    print_color $BLUE "Recommended versions: 3.11, 3.12, or 3.13"
}

# Function to fix common Python issues
fix_python_issues() {
    print_header "Fixing Common Python Issues"

    print_color $BLUE "Checking for common Python issues..."

    # Ensure 'python' symlink exists
    if ! command_exists python; then
        print_color $YELLOW "Issue: 'python' command not available"
        print_color $BLUE "Creating 'python' symlink..."

        local brew_prefix
        if [[ $(uname -m) == "arm64" ]]; then
            brew_prefix="/opt/homebrew"
        else
            brew_prefix="/usr/local"
        fi

        if [[ -f "$brew_prefix/bin/python3" ]]; then
            ln -sf "$brew_prefix/bin/python3" "$brew_prefix/bin/python"
            print_color $GREEN "✓ Created 'python' symlink"
        else
            print_color $RED "✗ python3 not found in expected location"
        fi
    else
        print_color $GREEN "✓ 'python' command is available"
    fi

    # Ensure 'pip' symlink exists
    if ! command_exists pip; then
        print_color $YELLOW "Issue: 'pip' command not available"
        print_color $BLUE "Creating 'pip' symlink..."

        local brew_prefix
        if [[ $(uname -m) == "arm64" ]]; then
            brew_prefix="/opt/homebrew"
        else
            brew_prefix="/usr/local"
        fi

        if [[ -f "$brew_prefix/bin/pip3" ]]; then
            ln -sf "$brew_prefix/bin/pip3" "$brew_prefix/bin/pip"
            print_color $GREEN "✓ Created 'pip' symlink"
        else
            print_color $RED "✗ pip3 not found in expected location"
        fi
    else
        print_color $GREEN "✓ 'pip' command is available"
    fi

    # PATH reminder
    local shell_config
    shell_config=$(get_shell_config)
    print_color $BLUE "If changes don't appear, reload your shell:"
    print_color $YELLOW "source $shell_config"

    # Attempt to refresh brew links for common versions
    print_color $BLUE "Refreshing Homebrew links for Python (if installed)..."
    brew link --overwrite python@3.12 2>/dev/null || true
    brew link --overwrite python@3.11 2>/dev/null || true
    brew link --overwrite python@3.13 2>/dev/null || true

    print_color $GREEN "✓ Common issues check completed"
}

# Menu
show_menu() {
    clear
    print_header "Python Installation for macOS"
    print_color $BLUE "Supported versions: Python 3.11 • 3.12 • 3.13"
    echo
    print_color $BLUE "Detected system: macOS $(sw_vers -productVersion) ($(detect_arch))"
    print_color $BLUE "Current shell: $(detect_shell)"
    echo

    # Current Python status (brief)
    local current_version
    current_version=$(get_current_python_version)
    if [[ "$current_version" != "not installed" ]]; then
        print_color $GREEN "Current Python: $current_version"
    else
        print_color $YELLOW "No Python3 currently available"
    fi
    echo

    print_color $YELLOW "Choose your preferred Python version:"
    echo
    print_color $GREEN  "1) Python 3.12 (Recommended)"
    print_color $BLUE   "2) Python 3.11 (Stable)"
    print_color $PURPLE "3) Python 3.13 (Latest)"
    echo
    print_color $YELLOW "4) Show current Python status"
    print_color $YELLOW "5) Verify existing installation"
    print_color $YELLOW "6) Fix common issues"
    print_color $RED    "7) Exit"
    echo
}

# Handle Python selection
handle_python_choice() {
    local choice=$1
    local version=""

    case $choice in
        1) version="3.12" ;;
        2) version="3.11" ;;
        3) version="3.13" ;;
        *) print_color $RED "Invalid Python version choice"; return 1 ;;
    esac

    print_color $BLUE "You selected Python $version"
    echo
    print_color $YELLOW "This will:"
    print_color $YELLOW "1) Install Python $version via Homebrew"
    print_color $YELLOW "2) Set up 'python'/'python3' and 'pip'/'pip3' symlinks"
    print_color $YELLOW "3) Update your PATH in $(get_shell_config)"
    echo

    read -p "Do you want to continue? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        print_color $YELLOW "Installation cancelled."
        return 0
    fi

    check_homebrew
    install_python "$version"
    verify_installation && show_post_install
}

# Main script execution
main() {
    # macOS guard
    if [[ "$(uname)" != "Darwin" ]]; then
        print_color $RED "This script is designed for macOS only!"
        exit 1
    fi

    # Requirement
    if ! command_exists curl; then
        print_color $RED "curl is required but not installed. Please install curl first."
        exit 1
    fi

    while true; do
        show_menu
        read -p "Enter your choice (1-7): " choice

        case $choice in
            1|2|3)
                handle_python_choice "$choice"
                read -p "Press Enter to continue..."
                ;;
            4)
                show_python_status
                read -p "Press Enter to continue..."
                ;;
            5)
                verify_installation
                read -p "Press Enter to continue..."
                ;;
            6)
                fix_python_issues
                read -p "Press Enter to continue..."
                ;;
            7)
                print_color $GREEN "Goodbye!"
                exit 0
                ;;
            *)
                print_color $RED "Invalid option. Please choose 1-7."
                sleep 2
                ;;
        esac
    done
}

# Cleanup function
cleanup() {
    print_color $YELLOW "\nScript interrupted. Cleaning up..."
    exit 1
}
trap cleanup SIGINT SIGTERM

# Welcome
print_header "Welcome to the Python Installer for macOS"
print_color $PURPLE "This script installs Python 3.11, 3.12, or 3.13 via Homebrew"
print_color $PURPLE "and configures your shell so the version you choose is the default."
echo
print_color $BLUE "Features:"
print_color $BLUE "• Interactive installation process"
print_color $BLUE "• Automatic PATH configuration"
print_color $BLUE "• Sets up 'python' and 'pip' convenience commands"
print_color $BLUE "• Supports Intel and Apple Silicon Macs"
echo
read -p "Press Enter to continue..."

# Run main
main "$@"
