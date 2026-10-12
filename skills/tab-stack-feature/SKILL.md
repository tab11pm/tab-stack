---
name: tab-stack-feature
description: "Prepare a tab-stack feature for review: port selected desktop changes into the source checkout, start a branch from fresh origin/main, validate and commit the feature, and publish to the user's fork when requested. Use for packaging a completed feature or taking a new tab-stack feature through the Git/PR workflow."
---

# tab-stack feature workflow

The project is **tab11pm/tab-stack**, a fork of howdeploy/kisa-stack. The fork is
the development and PR destination; the parent supplies provenance and licensing.
Use `tab-stack` branding and preserve existing attribution.

This skill handles feature packaging and Git delivery. It does not replace the
implementation task or authorize unrelated desktop installation or restarts.
If the user asks for a new feature, implement it as well; if they ask to package
an existing feature, identify and transfer that feature's changes only.

## Locate the source and scope

Locate the checkout from the current workspace or `$HOME/Projects/tab-stack`.
Read its `AGENTS.md` and contributor instructions for paths being changed. For
desktop publication, read `dotfiles/AGENTS.md`, `dotfiles/README.md` and the relevant
page in `dotfiles/docs/`.

Inspect the branch, working tree, index and remotes before mutation. Distinguish:

- Installed desktop: `${XDG_CONFIG_HOME:-$HOME/.config}/shoji-shell` and `shojiwm`.
- Publication source: `dotfiles/config/shoji-shell` and `shojiwm` in the checkout.
- Skill packages: `skills/<name>` in the checkout.

Port an installed feature only when synchronization is requested. Use a known
before/after diff or inspect the changed functions and their callers. Do not copy
the entire installed configuration: it can contain unrelated integrations,
machine defaults and other features. Adapt the delta to the repository's existing
components and sanitized defaults. Preserve opt-in flags and preset membership.

Do not include credentials, integration settings, photos, account/session data,
wallpaper/group selections, backups, caches or generated binaries. For a feature
with new persistent state, check both publication exclusions and preservation
during installer updates.

## Start from fresh main without disturbing other work

Verify that `origin` resolves to `tab11pm/tab-stack`, accepting HTTPS or SSH URLs.
Do not silently replace a differently configured remote. Fetch `origin main` and
inspect its resulting commit before describing the base as current.

If fetching fails, report the actual failure and provide:

```bash
git -C "$repo" fetch origin main
```

Independent feature preparation may continue, but label a cached base provisional.
After the user fetches, re-read `origin/main` and integrate that base. Do not claim
the fetch or update succeeded from a command suggestion alone. Stop repeating a
network/authentication attempt when there is no new information.

Use a descriptive `feature/<slug>` branch from the fetched `origin/main`, without
setting it to track `origin/main`. Inspect an existing feature branch before
reusing it. If the current checkout contains another task, use a separate worktree
instead of stashing, resetting, switching or committing that task's changes.
Record the target checkout and branch; recheck them before staging and committing,
because the user may run Git commands concurrently.

If updating the feature onto newer main causes conflicts, resolve them while
retaining both the feature and main's changes. Leave no conflict markers or
unmerged paths. Do not force-push a branch to solve a local preparation problem.

## Validate and create an actual feature commit

Run checks relevant to the changed behavior and required by the repository.
For desktop QML, use the installed **Qt 6** `qmllint`; `/usr/bin/qmllint` may be
Qt 5 and reject modern QML. For collectors, prefer their `--self-check` mode.
Do not start authenticated integrations just to validate packaging.

For installer changes, test only in an isolated target home. Compile required
Qt shaders only when needed for that check; keep generated `.qsb` files out of
the index. Distinguish source checks, isolated UI rendering, installed desktop
checks and user acceptance. Preserve warning/limitation details in the handoff.

Stage explicit reviewed paths. Inspect the exact staged diff and file list;
`git add .` can accidentally include another task. For desktop publication, run
the repository privacy checker against index blobs and the whitespace check:

```bash
python3 dotfiles/scripts/check-public.py --staged
git diff --cached --check
```

For skills outside that checker's configured scopes, review their staged content
directly for private paths/data rather than claiming the checker covered them.
Use the skill creator's validator when available for new or updated skills.

Check `git var GIT_AUTHOR_IDENT` without printing the identity. If Git has no
author configured, do not invent one, borrow a previous contributor's identity
or change global settings. Use identity information the user supplied, or leave
the reviewed changes staged and give local `git config user.name/user.email`
commands with clearly marked placeholders followed by the commit command.

Create a concise imperative feature commit when local committing is in scope.
Record the successful commit hash. **Staged files are not a commit**: do not
continue to push/create a PR or report a completed commit after `git commit`
fails. Confirm that `origin/main..HEAD` contains a feature commit and a meaningful
feature diff, not merely old main history.

## Publish to the fork when requested

When the user's request includes pushing or creating a PR, that is authorization
for the corresponding action; do not ask again. A bare skill invocation or local
preparation request does not add publication authority. Complete the local work
and provide publication commands when that is the requested endpoint.

Push the feature branch to **origin**, then verify the published branch points to
the intended commit. Specify the fork explicitly for every GitHub CLI operation;
`gh` can otherwise choose the upstream parent of a fork.

Before creation, check for an existing PR for the same branch in this fork. Reuse
it when appropriate instead of creating a duplicate. For a new PR, use:

```bash
gh pr create --repo tab11pm/tab-stack --base main --head "$branch" \
  --title "$title" --body-file "$pr_body_file"
```

Write the English PR title/body for a reviewer who has not seen the conversation:
state the problem, resulting behavior and relevant validation/limitations. Use a
temporary UTF-8 body file to preserve actual newlines. For UI changes, follow the
repository's screenshot requirements and use sanitized evidence; avoid personal
wallpapers, accounts or other private content in public screenshots.

For “No commits between” or blank-ref errors, inspect the actual local commit,
published head, chosen repository and base/head comparison before retrying.
Do not repeat the same failing PR command, create an empty commit to bypass the
error or push changes to the upstream parent.

Finish with the checkout/branch, commit hash or explicit staged-only status,
checks and material warnings, and the PR URL or exact remaining commands. Keep
unfinished fetch, commit, push and PR steps clearly distinguished.

Example requests:

- `$tab-stack-feature перенеси готовую группировку обоев в стек и подготовь коммит`
- `$tab-stack-feature добавь новую фичу в tab-stack и создай PR в мой форк`
- `$tab-stack-feature проверь ветку и исправь ошибку создания PR`
