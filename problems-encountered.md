# fluxNIC — Problems Encountered

Bugs, environment gotchas, and how they were solved. Newest at the top. Each
entry: what broke, why, and the fix — so the same wall is only hit once.

---

## 2026-09-01 — cocotb won't install on Python 3.14

**Symptom:** `pip install cocotb` failed with
`RuntimeError: cocotb 2.0.1 only supports a maximum Python version of 3.13.`

**Cause:** Ubuntu 26.04 ships Python 3.14 as its default `python3`. cocotb 2.0.1
does not yet support 3.14.

**Fix:** Installed a standalone Python 3.13 with uv and built the project venv on
it, so the system Python is left untouched:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
uv python install 3.13
uv venv --python 3.13 .venv
uv pip install --python .venv/bin/python cocotb
```

**Lesson:** pin the interpreter for tools with strict version ceilings; don't
rely on the distro default.

---

## 2026-09-01 — WSL project on /mnt/c is slow

**Symptom:** uv warned it could not hardlink files and fell back to full copies.

**Cause:** the project lives on `/mnt/c/...` (the Windows filesystem seen from
WSL). Cross-filesystem operations there are slower than on WSL's native ext4.

**Status:** accepted for now — fine for small simulations, keeps the files
reachable from Windows editors and Vivado. Revisit (move to `~/` in WSL) only if
simulation time becomes a bottleneck.
