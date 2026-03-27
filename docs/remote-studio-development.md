# Remote Studio Development

Use this repo so Studio execution can move between machines without committing machine-specific hostnames, usernames, paths, or secrets.

## Rules

- Keep remote host aliases and machine-specific paths in `scripts/remote_studio_profiles.local.sh`, not in committed scripts.
- Use `scripts/remote_studio_profiles.example.sh` as the starting template.
- Treat `primary` and `tertiary` as profile aliases and machine roles, not as committed transport details.
- Prefer direct development on the chosen dev machine when possible.
- Use the remote harness wrapper when Studio must run on another machine from the one holding your current worktree.

## Direct Development On The Active Dev Machine

1. Run the machine bootstrap once:

```bash
bash scripts/setup_remote_dev_machine.sh
```

This standardizes the expected Homebrew toolchain (`tmux`, `mosh`, `uv`) and installs the shared tmux overlay used by Blink/Termius remote sessions.

2. Keep a normal clone or worktree of `arnis-roblox` on the current development machine.
3. Keep the adjacent `vertigo-sync` repo on that same machine.
4. Run the local harness there:

```bash
bash scripts/run_studio_harness.sh --no-play --edit-tests
```

That path is the simplest and should be the default when `primary` is acting as the active development machine.

## Remote Terminal Development

After `bash scripts/setup_remote_dev_machine.sh` has run on a remote macOS machine:

- use Tailscale/SSH aliases from your ignored local profile config
- use `mosh <profile>` from Blink or Termius when the machine has a working Tailscale install
- land in a persistent tmux session with a command like:

```bash
mosh primary -- tmux new -A -s dev
mosh tertiary -- tmux new -A -s dev
```

If Tailscale is installed but still needs an interactive admin or sign-in step, the setup script should report that explicitly instead of pretending the machine is ready.

## Remote Harness From Another Machine

1. Copy the template:

```bash
cp scripts/remote_studio_profiles.example.sh scripts/remote_studio_profiles.local.sh
```

2. Fill in your local SSH aliases or transport targets for the `primary` and `tertiary` profiles.
3. Run the remote wrapper with the chosen profile:

```bash
bash scripts/run_studio_harness_remote.sh --remote-profile primary -- --no-play --edit-tests
bash scripts/run_studio_harness_remote.sh --remote-profile tertiary -- --no-play --edit-tests
```

## Notes

- The committed wrapper supports profile aliases, but not committed real hostnames, usernames, IPs, or `.local` machine names.
- Remote stage paths default to `__REMOTE_HOME__/...` templates and expand on the remote machine.
- Fresh remote machines do not need pre-seeded sibling clones; the first synced run can seed the remote stage directly from the current worktree snapshot.
- Remote snapshot sync transfers tracked files and untracked non-ignored files only. Keep `.gitignore` current so generated `target`, `out`, `dist`, `build`, cache, and dependency trees never transfer into remote stages.
- Do not disable SSH host-key verification in committed scripts. Accept or rotate host keys out-of-band on each operator machine before using a new remote profile.
- If a host has no local profile config, the wrapper should fail early with a clear configuration error instead of guessing.
