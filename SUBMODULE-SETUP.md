\# Setting Up the Hartz Claude Framework as a Git Submodule



Once set up, updating the framework across ALL your projects becomes one command per project.



---



\## What is a submodule?



A Git submodule is a link from your project repo to another repo (the framework).

Instead of copying files manually, your project just points to a specific version

of the framework. When the framework updates, you pull the update into each project

with two commands.



---



\## One-time setup per project



Do this for each existing project (UNION Spaces Core, client projects, etc).



\### Step 1 — Remove the manually copied framework files



In PowerShell, from your project root:



```powershell

\# Remove the files you copied manually

\# (the submodule will replace them)

Remove-Item -Recurse -Force .claude\\hooks\\pre-deploy.sh

Remove-Item -Recurse -Force .claude\\hooks\\task-completed.sh

Remove-Item -Recurse -Force .claude\\commands\\review.md

Remove-Item -Recurse -Force .claude\\commands\\compound.md

Remove-Item -Recurse -Force .claude\\commands\\prd.md

Remove-Item -Recurse -Force .claude\\commands\\bugfix.md

Remove-Item -Recurse -Force .claude\\commands\\task.md

Remove-Item -Recurse -Force .claude\\agents\\

Remove-Item -Recurse -Force scripts\\ralph.sh

Remove-Item -Recurse -Force scripts\\quality-gate.sh

```



> Note: Keep your project-specific CLAUDE.md — do NOT delete that.



\### Step 2 — Add the framework as a submodule



```powershell

git submodule add https://github.com/Hartz-AI/claude-framework .claude-framework

```



This creates a `.claude-framework/` folder in your project linked to the framework repo.



\### Step 3 — Run the installer



```powershell

bash .claude-framework/install.sh .

```



This copies all the framework files (agents, commands, hooks, scripts) into your

project from the submodule. It will skip your existing CLAUDE.md and PROGRESS.md.



\### Step 4 — Commit



```powershell

git add .

git commit -m "chore: add Hartz Claude Framework as submodule"

git push origin staging/batch-changes

```



---



\## Updating the framework across all projects



When the framework repo gets new changes (new agents, updated commands, bug fixes):



\### Step 1 — Pull the update into each project



```powershell

cd C:\\Users\\craig\\Documents\\Projects\\\[your-project]

cd .claude-framework

git pull origin master

cd ..

bash .claude-framework/install.sh .

```



\### Step 2 — Commit the submodule pointer update



```powershell

git add .claude-framework

git commit -m "chore: update Claude framework to latest"

git push origin staging/batch-changes

```



That's it. Two commands (plus a commit) per project.



---



\## For brand new projects



The full new project setup becomes:



```powershell

\# Create project

mkdir my-new-project

cd my-new-project

git init



\# Add framework

git submodule add https://github.com/Hartz-AI/claude-framework .claude-framework

bash .claude-framework/install.sh .



\# Edit CLAUDE.md — fill in the project name, tech stack, description

\# Then commit

git add .

git commit -m "feat: initial project setup with Hartz Claude Framework"

```



---



\## Useful submodule commands



| Command | What it does |

|---------|-------------|

| `git submodule update --init` | Initialise submodule after cloning a project for the first time |

| `git submodule update --remote` | Pull latest framework into all submodules at once |

| `git submodule status` | Check which version of the framework each project is pointing to |



---



\## If a colleague clones your project



They need to run this once after cloning:



```powershell

git submodule update --init --recursive

bash .claude-framework/install.sh .

```



Or clone with submodules included from the start:



```powershell

git clone --recurse-submodules https://github.com/your-org/your-project.git

```

