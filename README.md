# NodeBar

NodeBar is a tiny, native macOS menu bar app for keeping track of local Node.js servers. It lists current-user TCP listeners with their project directory, ports, and PID, then lets you stop a server or review a restart on another port.

It is dependency-free, runs as a menu bar accessory, and does not add a Dock icon or require administrator access.

## Requirements

- macOS 13 or newer
- Swift 5.10 or newer with the Xcode Command Line Tools

## Build and run

```sh
git clone https://github.com/mholyjr/nodebar.git
cd nodebar
./build-app.sh
open NodeBar.app
```

The build script creates and ad-hoc signs `NodeBar.app` for local use.

## Features

- Lists Node.js processes that own TCP listeners for the current user.
- Deduplicates IPv4 and IPv6 bindings while keeping the listening ports visible.
- Refreshes automatically and provides a manual refresh action.
- Stops a selected PID with `SIGTERM`, then offers an explicit `SIGKILL` after another identity check if it does not exit.
- Validates a new port and the original process identity before a restart.
- Shows the project directory and keeps the full command available in the row tooltip.

## Changing ports

NodeBar can prepare a reviewed `--port` suggestion for recognizable Vite and Next CLI commands. For other processes, enter the command you normally use to start the server; NodeBar does not assume that an arbitrary Node process honors a port flag.

The optional `PORT` setting is opt-in and only works when the framework reads that environment variable. Restarts run the reviewed command in the project directory through a login `zsh` environment. The original process environment is not copied.

Restart output is appended to `~/Library/Logs/NodeBar/restarts.log` when a command needs investigation. NodeBar sends signals only to the selected PID and never to a process group.

## Command-line listing

For a machine-readable snapshot without opening the menu bar app:

```sh
NodeBar.app/Contents/MacOS/NodeBar --list
```

The command prints JSON containing PIDs, ports, project names, and working directories.

## Contributing

There is no formal contribution process yet. Open an issue or pull request with a focused change and include the macOS version and reproduction steps when reporting a problem.

NodeBar is released under the [MIT License](LICENSE).
