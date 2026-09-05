# NodeBar

NodeBar is a small macOS menu bar app that shows listening TCP servers owned by the current user whose executable is Node.js. It discovers listeners through `lsof`, shows their PID, ports, project directory, and command, and can stop a process or review a restart on a different port.

## Build

```sh
./build-app.sh
open NodeBar.app
```

The app requires macOS 13 or newer. It runs as a menu bar accessory and does not put a window or Dock icon on screen.

## Process actions

Stop sends `SIGTERM` to the selected PID after rechecking its identity. If it remains alive, NodeBar offers an explicit force-kill action that sends `SIGKILL` only after another identity check.

Changing a port first checks that the requested port is free and rechecks the original process. Vite and Next CLI commands receive an updated `--port` argument when NodeBar can identify those CLIs. Other commands stay editable; an optional `PORT` environment prefix is available with a note that support depends on the framework. The restart runs in the project directory through a login zsh environment, and the original process environment is not copied.

NodeBar never kills a process group or logs process command lines, because command lines can contain credentials. Restart stdout and stderr are appended to `~/Library/Logs/NodeBar/restarts.log` so failed launches can be inspected.
