# Z-G-R: A GitHub Release Package Manager for Zsh

Z-G-R is a plugin helps you to install binaries from GitHub releases (fzf, bat, eza, lazygit and [more](https://github.com/ibraheemdev/modern-unix)).

Z-G-R allows you to easily install, uninstall, and manage binaries from GitHub releases. It handles:

- Automatic detection of appropriate assets for your system architecture and OS
- Downloading and extracting archives
- Setting up binary and completion files using symbolic links, without messing up your `$path` and `$fpath`
- Executing post-installation commands

## Installation

### Oh My Zsh

Clone the repository and add `z-g-r` to your `plugins` array in `.zshrc`:

```zsh
git clone https://github.com/cgjosephlee/z-g-r.git ${ZSH_CUSTOM}/plugins/z-g-r
```

Then, in your `.zshrc`, add `z-g-r` to the list of plugins:

```zsh
plugins=(... z-g-r)
```

### Antidote

Add to your `.zsh_plugins.txt`:

```
cgjosephlee/z-g-r
```

### Sheldon

Add to your `plugins.toml`:

```toml
[plugins.z-g-r]
github = "cgjosephlee/z-g-r"
```
### Zimfw

Add to your `.zimrc`:

```zsh
zmodule cgjosephlee/z-g-r
```

### Zinit

Add to your `.zshrc`:

```zsh
zinit light cgjosephlee/z-g-r
```

## Usage

### Configuration

Z-G-R uses the following environment variables which can be set in your `.zshrc`:

```zsh
# Main configuration file
ZGR_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/zgr/config.zsh"
# or disable configuration file and put your settings in .zshrc
ZGR_CONFIG=0

# Directory structure
ZGR_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/zgr"
ZGR_BIN_DIR="$ZGR_DIR/bin"
ZGR_COMP_DIR="$ZGR_DIR/completions"
ZGR_PKG_DIR="$ZGR_DIR/pkgs"

# Use GitHub API (default)
GITHUB_TOKEN=  # Provide your token if you hit limits
ZGR_USE_GITHUB_API=1
# or old-fashion web scraping
ZGR_USE_GITHUB_API=0

# Enable debug output
ZGR_DEBUG=1
```

Add installation commands to your `$ZGR_CONFIG` and Z-G-R will source it.

### Install packages

Basic syntax for installing packages:

```zsh
zgr-install [options] username/repo
```

Example with all options:

```zsh
zgr-install \
    --if '[[ -n $SOME_STATUS ]]' \
    --ver 'v1.2.3' \
    --pick '*musl*' \
    --exec 'wget -q https://some/script' \
    --exec './binary completion zsh > _binary' \
    --bin 'binary*' \
    --comp '**/_binary' \
    --src 'script-to-source.zsh' \
    username/repo
```

Options:

| Option   | Description                                                                 | Usage     |
|----------|-----------------------------------------------------------------------------|-----------|
| `--if`   | Conditional expression; installs the package only if this evaluates to true | Once      |
| `--ver`  | Specify the version tag to install (defaults to "latest" if omitted)        | Once      |
| `--pick` | Filter release assets by glob pattern                                       | Once      |
| `--exec` | Command to execute after installation (runs in the package directory)       | Multiple  |
| `--bin`  | Binary files to be linked                                                   | Multiple  |
| `--comp` | Completion files to be linked                                               | Multiple  |
| `--src`  | Scripts to source after installation                                        | Multiple  |

For `--bin` and `--comp`, you can use:
- Simple format: `"filename"`
- Rename format: `"source_file -> target_name"`

### Uninstall

```zsh
# Uninstall a package
zgr-uninstall user/repo

# Clean unused packages
zgr-clean
# or clean all packages
_ZGR_INSTALLED=() zgr-clean
```

## Examples

See https://github.com/cgjosephlee/z-g-r/blob/main/examples/config.zsh.

## Credits

- Z-G-R is inspired by the GitHub release handling functionality in [Zinit](https://github.com/zdharma-continuum/zinit).
- JSON parsing functionality is based on [JSON.sh](https://github.com/dominictarr/JSON.sh).
