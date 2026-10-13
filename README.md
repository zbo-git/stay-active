# stay-active

A lightweight macOS Bash utility that periodically generates synthetic keyboard input, and optionally small cursor movements. This fork of [sleekhost/stay-active](https://github.com/sleekhost/stay-active) focuses on safer process management, clearer logging, and less interference with normal work.

> **Important:** Synthetic input does not guarantee that Microsoft Teams or any other application will show you as **Active**. Presence may also depend on application state, screen lock, sleep, and organizational policies. This project makes no claim that its input is indistinguishable from human activity or undetectable.

## Features

| Feature | Behavior |
| --- | --- |
| Lightweight utility | Bash script using `cliclick` on macOS |
| Synthetic keyboard input | Sends a Shift press/release when the system meets the configured idle threshold |
| Optional cursor movement | Small randomized offset, **disabled by default** |
| Randomized intervals | Checks roughly every 30–60 seconds |
| Idle awareness | Skips input when the macOS HID idle time is below the threshold (60 seconds by default) |
| Process safety | Atomic startup lock and process-command checks before termination |
| Logging | Records skipped input, simulated input, and operational errors |
| Optional login startup | User-level macOS LaunchAgent with periodic retry |

## Requirements

- macOS, with Bash and `ioreg` available
- [Homebrew](https://brew.sh/) (for the included installer)
- [`cliclick`](https://github.com/BlueM/cliclick), installed via Homebrew
- Accessibility permission for the terminal and/or relevant `cliclick` executable

The original project documented macOS 10.13+; this fork has **not** been compatibility-tested across macOS releases.

## Installation

### Recommended: install from your checked-out fork

On a Mac:

```bash
git clone https://github.com/zbo-git/stay-active.git
cd stay-active
bash install.sh
```

If reviewing an unmerged PR, switch to its branch **before** running `bash install.sh`. The installer copies the local `stay-active` script from the checkout to `~/.local/bin/stay-active`.

The installer requires Homebrew, installs `cliclick` if missing, and adds `~/.local/bin` to your shell PATH configuration if necessary. Open a new terminal, or run:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### Manual installation

```bash
brew install cliclick
mkdir -p ~/.local/bin
cp ./stay-active ~/.local/bin/stay-active
chmod +x ~/.local/bin/stay-active
```

Add `~/.local/bin` to your PATH if it is not already included.

### Grant Accessibility permissions

In **System Settings → Privacy & Security → Accessibility**, allow your terminal application and `cliclick` as needed. The executable may be in `/opt/homebrew/bin/cliclick` on Apple Silicon or `/usr/local/bin/cliclick` on Intel Macs. Exact permission behavior depends on your macOS version and how the utility is started.

## Usage

```bash
stay-active start         # Start detached background worker
stay-active status        # Check whether its process can be verified
stay-active log           # View recent log entries
stay-active stop          # Request a graceful stop
stay-active toggle        # Start or stop
stay-active autostart-on  # Install and load the login LaunchAgent
stay-active autostart-off # Unload and remove the LaunchAgent
stay-active --help        # Show command summary
stay-active --version     # Show version
```

`start` runs the worker independently of the invoking terminal using `nohup`. `status` reports the worker's verified process state; it does **not** report Microsoft Teams presence.

### Configuration

Set environment variables **when starting** the script:

| Variable | Default | Effect |
| --- | --- | --- |
| `STAY_ACTIVE_MIN_IDLE_SECONDS` | `60` | Minimum observed macOS HID idle time before synthetic input is sent; nonnegative integer |
| `STAY_ACTIVE_MOUSE` | `0` | `0`: keyboard only; `1`: additionally move cursor by a small offset |
| `STAY_ACTIVE_STATE_DIR` | `~/.local` | Directory for worker lock, PID and log files (advanced use) |

For example:

```bash
STAY_ACTIVE_MIN_IDLE_SECONDS=120 STAY_ACTIVE_MOUSE=0 stay-active start
```

The optional LaunchAgent starts with the default settings unless you explicitly configure its environment. Configuration values are not dynamically reloaded into an already-running worker.

## How it works

1. The worker reads the macOS HID idle-time counter using `ioreg`.
2. If the recorded idle duration is below the configured threshold, it skips synthetic input.
3. Otherwise, it sends a Shift key press/release through `cliclick`. When explicitly enabled, it also makes a small cursor movement.
4. It records the result and sleeps for approximately 30–60 seconds before checking again.
5. If idle-time inspection fails, the worker stops. Three consecutive failures to send input also cause it to exit.

HID idle time is an operating-system approximation. Synthetic events can affect idle-time reporting, and successful `cliclick` execution does not demonstrate a change to application presence.

## Optional automatic startup

```bash
stay-active autostart-on
```

This installs a user LaunchAgent at `~/Library/LaunchAgents/net.zbo.stay-active.plist`. It starts on login and periodically attempts to run `stay-active start` (approximately once per minute). This is a **retry mechanism**, not full process supervision.

**For an intentional stop, disable automatic startup first:**

```bash
stay-active autostart-off
stay-active stop
```

Otherwise the LaunchAgent may start a worker again. An unexpected worker crash may leave a stale lock requiring manual recovery rather than automatic restart.

## Troubleshooting

### `cliclick` not found

```bash
brew install cliclick
```

Make sure Homebrew's `bin` directory is on PATH.

### Accessibility errors or synthetic input not working

Review permissions in **System Settings → Privacy & Security → Accessibility**. Run `stay-active log` to see reported failures. The worker exits after three consecutive failed `cliclick` operations rather than silently claiming successful activity.

### A stale lock prevents startup

State is stored by default at:

```text
~/.local/.stay_active_pid
~/.local/.stay_active_lock/
~/.local/.stay_active_log
```

The worker deliberately refuses to remove an ambiguous lock or signal a PID it cannot verify. First inspect `stay-active status`, the PID file, and running processes. **Only after confirming no matching worker is running**, you can clear stale state:

```bash
rm -f ~/.local/.stay_active_pid
rmdir ~/.local/.stay_active_lock
stay-active start
```

Do not remove an active worker's lock. `rmdir` intentionally fails if the directory is not empty.

### Teams still shows Away

Check `stay-active status` and `stay-active log`, and verify the Mac is awake and Accessibility permission is granted. Teams can use signals beyond synthetic input. There is no supported guarantee that this utility changes its presence state.

### After sleep, login, or terminal close

Verify the worker with `stay-active status`. Test the optional LaunchAgent separately. Screen lock, sleep/wake and login behavior have not been validated for all environments.

## Development and testing

From the repository root:

```bash
bash -n stay-active install.sh uninstall.sh
bash tests/smoke.sh
```

These checks validate basic Bash syntax and selected process-safety behavior; they do **not** exercise macOS input injection or Teams integration.

Manual macOS QA is still needed for Accessibility denial or revocation, concurrent starts, repeated start/stop, stale-lock recovery, terminal closure, login startup, screen lock, sleep/wake, and application presence.

## Uninstall

From a checkout:

```bash
bash uninstall.sh
```

Or manually:

```bash
stay-active autostart-off
stay-active stop
rm -f ~/.local/bin/stay-active
```

Inspect state files before removing them manually if a worker may still be running. `cliclick` can optionally be removed using `brew uninstall cliclick` if no other programs need it.

## Privacy and security

The worker operates locally and does not include telemetry or a network service. It requires macOS Accessibility permissions to generate synthetic input. Review your organization's policies before using tools that alter apparent activity status.

## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md). Distributed under the [MIT License](LICENSE). Original project by [Sleekhost](https://github.com/sleekhost).
