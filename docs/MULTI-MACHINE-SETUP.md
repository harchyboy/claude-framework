# Multi-Machine Setup Guide

> How to set up and keep in sync the Hartz Claude Framework across multiple machines.

---

## Prerequisites

Install these on every machine. All commands are PowerShell (Windows).

### 1. Core runtime

```powershell
winget install OpenJS.NodeJS.LTS --source winget
winget install Python.Python.3.13 --source winget
winget install Git.Git --source winget
winget install jqlang.jq --source winget
```

Close and reopen PowerShell after installing so PATH updates take effect.

### 2. Enable PowerShell script execution

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

### 3. Install Claude Code

```powershell
npm install -g @anthropic-ai/claude-code
```

### 4. C++ build tools (required for native modules like node-pty)

If `npm install` fails on native modules, install build tools from an admin PowerShell:

```powershell
npm install -g windows-build-tools
```

Or install Visual Studio Build Tools with the "Desktop development with C++" workload.

### 5. Set your API key

```powershell
[Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", "sk-ant-your-key-here", "User")
```

### 6. Verify installation

```powershell
node --version      # v22+ or v24+
python --version    # 3.12+
git --version       # any recent version
jq --version        # any version
claude --version    # Claude Code CLI
```

---

## Clone all projects

Clone every project repo with submodules into the same folder structure on each machine:

```powershell
cd ~\Documents
mkdir Projects
cd Projects

git clone --recurse-submodules <repo-url> <folder-name>
```

Use `--recurse-submodules` to automatically pull down the `.claude-framework` submodule.

If you already cloned without that flag, initialise submodules after the fact:

```powershell
git -C <folder-name> submodule update --init --recursive
```

### Install the framework into each project

For every project that has a `.claude-framework` folder:

```powershell
bash <project-folder>/.claude-framework/install.sh <project-folder>
```

This copies agents, commands, hooks, scripts, and merges settings into each project.

---

## Global Claude settings

Create the global settings file at `C:\Users\<username>\.claude\settings.json`:

```powershell
New-Item -ItemType Directory -Path C:\Users\<username>\.claude -Force
notepad C:\Users\<username>\.claude\settings.json
```

Paste the following and save:

```json
{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Edit",
      "Write",
      "WebSearch",
      "WebFetch(*)",
      "Skill(*)"
    ]
  },
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

---

## Hartz Command (optional — if using the orchestration dashboard)

```powershell
cd ~\Documents\Projects\hartz-command
npm install
npm run db:migrate
npm run dev
```

Then deploy hooks to all projects (in a second terminal while the server is running):

```powershell
cd ~\Documents\Projects\hartz-command
bash scripts/hooks/deploy-hooks.sh
```

---

## Keeping machines in sync

Git is the sync mechanism. Each machine has its own local clone of every repo, synced via GitHub.

### Daily workflow

**On the machine where you made changes:**

```powershell
git add .
git commit -m "your message"
git push
```

**On the other machine, before starting work:**

```powershell
git pull
```

### After a framework update

On the machine where the framework was updated:

```powershell
cd <project>/.claude-framework
git pull origin master
cd ..
bash .claude-framework/install.sh .
git add .
git commit -m "chore: update claude framework"
git push
```

On the other machine:

```powershell
git pull
git submodule update --init --recursive
bash .claude-framework/install.sh .
```

Or use the sync script to push to all projects at once:

```powershell
cd ~\Documents\Projects\hartz-claude-framework
bash scripts/sync.sh push
```

### What stays local (not synced)

These are machine-specific and not tracked in git:

| Item | Location | Why it's local |
|------|----------|---------------|
| SQLite database | `hartz-command.db` | Each machine tracks its own agent sessions |
| File uploads | `~/.hartz-command/uploads/` | Uploaded via local dashboard |
| Global Claude settings | `~/.claude/settings.json` | Machine-specific permissions |
| Node modules | `node_modules/` | Rebuilt per machine via `npm install` |
| API keys | Environment variable | Never committed to git |

### If package.json changed on the other machine

After `git pull`, if `package.json` was modified:

```powershell
npm install
```

### If migrations were added on the other machine

After `git pull`, if new `.sql` migration files appeared:

```powershell
npm run db:migrate
```

---

## Troubleshooting

### npm install fails on node-pty

Install C++ build tools (see Prerequisites step 4).

### PowerShell blocks script execution

Run `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`.

### Hook scripts fail with "python not found"

Ensure Python is on your PATH. Close and reopen PowerShell after installing Python.

### Notepad saves as .json.txt

When using "Save As", change "Save as type" from "Text documents (*.txt)" to "All files (*.*)".

### deploy-hooks.sh fails

Ensure jq is installed (`jq --version`) and the Hartz Command server is running on port 3001.
