#!/bin/bash

# Bumpster installation script

### Begin define variables ###
home=$(sh -c "echo ~$(whoami)")  # Define user's home directory
install_dir="$home/.bumpster"    # Directory where Bumpster will be installed
bin_dir="$install_dir/bin"       # Directory for binary files
lib_dir="$install_dir/lib"       # Directory for library files
version_url="https://github.com/phoenixweiss/bumpster/archive/refs/heads/main.tar.gz" # GitHub archive URL
ostype=$(uname -s)               # Detect the OS type
### End define variables ###

# Check for required tools
if ! command -v curl &> /dev/null; then
  echo "curl is required for installation. Please install curl and try again."
  exit 1
fi

# Create the necessary directories if they do not exist
mkdir -p "$bin_dir" "$lib_dir"

# Download and extract the latest version of Bumpster from GitHub
echo "Downloading and installing the latest version of Bumpster..."
curl -L -# "$version_url" | tar -zxf - --strip-components 1 -C "$install_dir"

# Make the script executable
chmod +x "$bin_dir/bumpster.sh"

# Determine the correct shell configuration file
if [[ "$ostype" == "MINGW"* || "$ostype" == "CYGWIN"* ]]; then
  # For Git Bash on Windows, use ~/.bash_profile
  shell_config="$home/.bash_profile"
else
  # For Unix-like systems, use ~/.bashrc or ~/.zshrc
  if [ -f "$home/.bashrc" ]; then
    shell_config="$home/.bashrc"
    elif [ -f "$home/.zshrc" ]; then
    shell_config="$home/.zshrc"
  else
    # Default to ~/.bashrc if no shell config is found
    shell_config="$home/.bashrc"
    touch "$shell_config"
  fi
fi

# Add Bumpster to PATH if it's not already present
if ! grep -q "$bin_dir" "$shell_config"; then
  echo "export PATH=\"$bin_dir:\$PATH\"" >> "$shell_config"
  echo "Bumpster has been added to your PATH in $shell_config."
else
  echo "Bumpster is already in your PATH."
fi

# Provide instructions for adding Bumpster to PATH
echo "Bumpster installed successfully in $bin_dir!"
echo "To use Bumpster, add the following line to your shell configuration file (if not already added):"
echo "  export PATH=\"$bin_dir:\$PATH\""
echo "Then, run 'source $shell_config' (or the equivalent for your shell) to reload the environment."

# Check version information
if [ -f "$install_dir/VERSION" ]; then
  local_version=$(cat "$install_dir/VERSION")
  remote_version=$(curl -s https://raw.githubusercontent.com/phoenixweiss/bumpster/main/VERSION)

  if [ "$local_version" != "$remote_version" ]; then
    echo "A new version of Bumpster is available: $remote_version (current: $local_version)."
    echo "Please update Bumpster by running this install script again."
  else
    echo "You are using the latest version of Bumpster ($local_version)."
  fi
fi

# Final message
echo "Bumpster installation completed. You can now use the 'bumpster' command from any directory after adding it to your PATH."
