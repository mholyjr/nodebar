# NodeBar

NodeBar is a tiny, native macOS menu bar app for keeping track of local Node.js servers. It lists current-user TCP listeners with their project directory, ports, and PID, lets you stop or start saved servers, and lets you review a restart on another port.

It is dependency-free, runs as a menu bar accessory, and does not add a Dock icon or require administrator access. Server profiles are saved in `~/Library/Application Support/NodeBar/profiles.json` with user-only file permissions.

## Requirements

- macOS 13 or newer
- Xcode 26 or the Xcode 26 Command Line Tools, providing Swift 6.2 and the macOS 26 SDK for the build
- `lsof` for listener discovery

On macOS 26 and newer the panel uses `NSGlassEffectView` for the system glass treatment. On macOS 13–25 it uses the compatible popover visual-effect material, while keeping the same native controls and layout.

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
- Retains stopped server profiles across launches, with Start, Stop, Configure, and Forget actions.
- Remembers a preferred port for each profile. NodeBar applies that preference only when NodeBar starts the server; it does not change externally launched processes.
- Loads saved profiles without starting them automatically. Saving Configure changes also leaves the server stopped or running until you choose Start or Restart.
- Labels recognized Node, Next, Vite, Nuxt, and Astro projects with a compact framework badge.
- Stops a selected PID with `SIGTERM`, then offers an explicit `SIGKILL` after another identity check if it does not exit.
- Validates a new port and the original process identity before a restart.
- Shows the project directory and keeps the full command available in the row tooltip.

## Changing ports

NodeBar first checks the server's project directory and its bounded set of ancestors for `package.json`. It reads the package name, scripts, framework dependencies, and package manager metadata without executing any scripts. The `packageManager` field wins; otherwise NodeBar uses the nearest npm, pnpm, Yarn, or Bun lockfile.

For recognized Next, Vite, Nuxt, and Astro projects, NodeBar suggests a `dev`, `start`, `preview`, or similarly named package script when its command directly invokes that framework. It invokes the script so its existing flags remain intact. For example, a pnpm project gets `pnpm run dev --port 3000`, while npm uses `npm run dev -- --port 3000`. When more than one suitable script exists, choose one from the selector in the Configure dialog. These are reviewed suggestions; NodeBar does not execute scripts to discover what they do.

For other processes, enter the command you normally use to start the server; NodeBar does not assume that an arbitrary Node process honors a port flag.

The optional `PORT` setting is opt-in and only works when the framework reads that environment variable. Restarts and NodeBar starts run the reviewed command in the project directory through a login `zsh` environment. The original process environment is not copied, so configure tools such as `nvm` in the login shell if the project needs them. If NodeBar cannot infer a safe command, the command field is left empty and must be filled in manually.

Restart output is appended to `~/Library/Logs/NodeBar/restarts.log` when a command needs investigation. NodeBar sends signals only to the selected PID and never to a process group.

NodeBar revalidates the selected process identity and port availability immediately before mutation, sends signals only to the selected PID, and never starts saved servers automatically when the app launches.

## Command-line listing

For a machine-readable snapshot without opening the menu bar app:

```sh
NodeBar.app/Contents/MacOS/NodeBar --list
```

The command prints JSON containing PIDs, ports, project names, and working directories.

## Contributing

There is no formal contribution process yet. Open an issue or pull request with a focused change and include the macOS version and reproduction steps when reporting a problem.

NodeBar is released under the [MIT License](LICENSE).
