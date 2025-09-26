# cli-tools

A personal collection of useful shell scripts for daily productivity and system administration tasks.

## Scripts Overview

### System Utilities
- `sysinfo` - Display comprehensive system information
- `cleanup` - Clean up temporary files and optimize system

### File Operations
- `backup` - Create backups of files and directories
- `findlarge` - Find large files on the system

### Network Utilities  
- `netcheck` - Check network connectivity and status
- `portcheck` - Check if specific ports are open

### Development Tools
- `gitclean` - Clean up Git repositories 
- `devsetup` - Setup development environment

## Installation

1. Clone this repository:
```bash
git clone https://github.com/sasmithaK/cli-tools.git
cd cli-tools
```

2. Make scripts executable:
```bash
chmod +x scripts/*
```

3. Add to your PATH (optional):
```bash
export PATH="$PATH:$(pwd)/scripts"
```

Or add this line to your `~/.bashrc` or `~/.zshrc`:
```bash
export PATH="$PATH:/path/to/cli-tools/scripts"
```

## Usage

Each script can be run directly:
```bash
./scripts/sysinfo
./scripts/backup /path/to/backup
./scripts/netcheck google.com
```

Run any script without arguments to see usage information.

## Requirements

- Bash 4.0+
- Standard Unix utilities (find, grep, awk, etc.)
- Some scripts may require additional tools (documented per script)