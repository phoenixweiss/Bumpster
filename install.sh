#!/bin/bash

# Bumpster installation script

### Begin define variables ###
home=$(sh -c "echo ~$(whoami)")  # Define user's home directory
BUMPSTER_HOME="$home/.bumpster"  # Directory where Bumpster will be installed
bin_dir="$BUMPSTER_HOME/bin"     # Directory for binary files
version_url="https://github.com/phoenixweiss/Bumpster/archive/refs/heads/main.tar.gz" # GitHub archive URL
### End define variables ###

# Check for required tools
if ! command -v curl &> /dev/null; then
  echo "curl is required for installation. Please install curl and try again."
  exit 1
fi

# Create the necessary directories if they do not exist
mkdir -p "$bin_dir"

# Download and extract the latest version of Bumpster from GitHub
echo "Downloading and installing the latest version of Bumpster..."
curl -L -# "$version_url" | tar -zxf - --strip-components 1 -C "$BUMPSTER_HOME"

# Source functions.sh
source "$BUMPSTER_HOME/config.sh"
source "$BUMPSTER_HOME/lib/functions.sh"

# Perform post-installation steps
post_install

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

# Final message
echo "Bumpster installation completed."
