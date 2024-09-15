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

# Move bumpster.sh to bin directory if not already there
if [ ! -f "$bin_dir/bumpster.sh" ]; then
  mv "$install_dir/bumpster.sh" "$bin_dir/"
fi

# Make the script executable
chmod +x "$bin_dir/bumpster.sh"

# Check if the bin directory is already in the PATH
if [[ ":$PATH:" == *":$bin_dir:"* ]]; then
  echo "Bumpster's bin directory is already in your PATH."
else
  echo "Bumpster has been installed successfully in $bin_dir."
  echo "However, to use Bumpster from any directory, you need to add it to your PATH."
  echo ""
  echo "Please manually add the following line to your shell configuration file (e.g., ~/.bashrc or ~/.bash_profile):"
  echo ""
  echo "  export PATH=\"$bin_dir:\$PATH\""
  echo ""
  echo "Then, reload your shell configuration by running:"
  echo "  source ~/.bashrc  # or the equivalent for your shell"
fi

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
echo "Bumpster installation completed."
