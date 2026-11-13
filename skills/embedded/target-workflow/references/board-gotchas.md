# Board gotchas

Things that cost real time on lab boards, and the fix.

## Reaching the board

- **DHCP leases shift.** A board's IP can change across reboots, even within a day, even across subnets. Set `TARGET_HOSTNAME` in `.target.env` so `target.sh` verifies it is talking to the right machine. "Connection refused" or a timeout on the last-known IP: ask the user for the current IP — don't guess octets.
- **Host key changed** after a reflash: plausibly benign on a lab network, but confirm with the user before `ssh-keygen -R <ip>`.
- **"Too many authentication failures"**: the agent offers many keys and the server's `MaxAuthTries` runs out before the right one. Pin the key in `~/.ssh/config` (`IdentityFile …` + `IdentitiesOnly yes`), or use `-o PubkeyAuthentication=no` once to `ssh-copy-id` the key back after a reflash wiped `authorized_keys`.
- **Backgrounding over ssh**: `ssh host 'nohup cmd &'` can hang the client for some tools even with redirects and `disown`. Use `ssh -f host 'cmd'`.
- **Long jobs die with the ssh session** — and a lab board on a portable payload gets power-cycled when someone moves it. Run long jobs detached on the board (`ssh -f`, or `nohup` writing a log), end the script with a sentinel line, and poll for it; keep captures you still need outside `/tmp`.
- **Non-interactive PATH**: tools like `nvcc` may be missing from a non-login shell's `PATH`. `target.sh` uses a login shell; if still missing, use the absolute path (`/usr/local/cuda/bin/nvcc`) or rely on the configured CMake cache.

## Builds

- **A 0-byte binary that CMake calls up to date**: an ssh drop mid-link truncates the output, timestamps still look satisfied, and the "built" binary exits instantly with no output. Delete the 0-byte binary (and any 0-byte `.o`) and rebuild.
- **A "2x regression" or a huge swing**: suspect a stale binary first; rebuild from clean before believing it.
- **Old CMake** (< 3.18) silently ignores `CMAKE_CUDA_ARCHITECTURES`; nvcc falls back to an old default arch that lacks fp16 intrinsics → link errors. Pass `-gencode arch=compute_XX,code=sm_XX` in `CMAKE_CUDA_FLAGS` explicitly. Changing `CMAKE_CUDA_COMPILER` needs `cmake` run twice.
- **Board clock far off** (no NTP, after power loss): make compares timestamps wrongly, rebuilds only part of the tree, and stale objects disagree on a struct's size — a segfault at init after adding a member. Fix the clock (`date`/NTP), then touch the sources or build clean.
- **Copying a binary package with `scp`/`cp` drops `.so` symlinks** — recreate them. `RUNPATH` covers the executable's direct dependencies only; libraries pulled in transitively still need `LD_LIBRARY_PATH`.
- New source files need a re-configure (`cmake .` in the build dir), not just `make`.
- **Board copies are not git repos** and drift from the source tree. Sync whole source directories (as `target.sh sync` does), not hand-picked files, before trusting a board build.

## Shared and production boards

- Production services (camera app, tracking, streaming) may run the whole time. They hold devices (the camera node) and load CPU/GPU: stop them only with the user's go-ahead, restart them afterwards, and label any measurement taken alongside them as shared-load.
- **Files edited directly on the board** (a build file that drifted ahead of the repo): before the first sync into an existing directory, pull and diff — `rsync` is one-way and silently overwrites board-side work.
- Other people's trees live on the same board — never touch anything outside `TARGET_DIR`.
- `/tmp` is cleared on reboot: never trust an old dump there; regenerate it in the same run. Write large repeated outputs to tmpfs (`/dev/shm`) to spare SD/eMMC wear.
- Root disks on boards fill up: check `df -h` before writing captures, dumps, or engines.

## Verify the commit, not the working tree

When the working tree also holds other uncommitted edits (someone else's WIP in the same files), building it proves nothing about your commit — the WIP fills the gaps.

1. `git worktree add --detach /tmp/wt HEAD`, apply only your change there.
2. Sync and build **that** tree on the board (`TARGET_DIR` pointing at a separate dir), verify the output.
3. Stage exactly those contents; afterwards `git diff HEAD` in the main tree should show only the other WIP.

Never split a change out with `git diff -U0 | git apply --cached --unidiff-zero` across shifted WIP — hunks land in the wrong place and the commit breaks the build.
