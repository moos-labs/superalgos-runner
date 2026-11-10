# superalgos-runner

Runs a time-boxed headless attempt at [Superalgos](https://github.com/Superalgos/Superalgos)
on GitHub Actions, where the commands to execute live in a repository
**Actions variable** — not in code.

Superalgos is a visual-first, crypto-focused algo-trading platform: strategies,
data-mines and backtesting sessions are built and run inside its graphical
workspace, not from a headless CLI. This runner therefore does **not** promise
a completed backtest. Its deliverable is an accurate map of how far headless
execution gets, with the exact blocking prerequisite quoted.

## The pattern (one repo per tool)

1. **Edit the commands**: repo *Settings → Secrets and variables → Actions →
   Variables* → set the `COMMANDS` variable to whatever shell commands this
   run should execute (multi-line works). The same can be done through the
   GitHub API (`PUT /repos/{owner}/{repo}/actions/variables/COMMANDS`).
2. **Trigger manually**: *Actions* tab → “Run analysis” → *Run workflow*
   (or `POST /repos/{owner}/{repo}/actions/workflows/run.yml/dispatches`).
   The workflow has **no other triggers** — it runs only when dispatched.
3. **Collect results**: the workflow uploads everything under `results/` as
   the `results` build artifact (`if: always()`, so partial results survive
   a failing step). Download it from the run page or via the API.

The workflow itself is generic: checkout → Node.js 20 (setup-node) →
run `${{ vars.COMMANDS }}` → upload `results/`. No Python is needed.
Node 20 is used because the Superalgos README requires Node.js >= 16 and
its own newer-Node instructions use `nvm install 20` as the example.

## Multi-market by design

Nothing in the workflow is tied to one exchange or market. The pilot script
takes no hard-coded ticker; a future run would pass project / workspace /
exchange parameters through `COMMANDS` — only the inputs change.

## Pilot: how far does headless Superalgos get?

Pilot `COMMANDS` value:

```sh
mkdir -p results
set -o pipefail; bash scripts/superalgos_attempt.sh 2>&1 | tee results/run.log
```

`scripts/superalgos_attempt.sh`:

1. Shallow-clones `Superalgos/Superalgos` (master, `--depth 1`, timeout 600s)
   and records the cloned commit, Node / npm / Git versions.
2. Follows the **current README in the clone**: `node setup` (timeout 1200s),
   then `node setupPlugins` with no arguments (timeout 120s) to capture the
   exact missing-prerequisite error — the README documents it as
   `node setupPlugins <Your-Github-Username> <Your-Github-Personal-Access-Token>`,
   forking every Community Plugins repo into that account. No token is
   invented or supplied in CI.
3. Attempts a headless start: `timeout 120 node platform minMemo noBrowser`,
   capturing stdout/stderr (`minMemo` = minimal memory, `noBrowser` = do not
   open the GUI, per the README Usage table).
4. Writes `results/attempt.md` with the commit, each step's return code and
   log tails, and the exact point where a headless backtest is blocked.
   Full logs (`clone.log`, `setup.log`, `setupPlugins.log`, `platform.log`)
   are in the same artifact. The script exits 0 after documenting the
   attempt, so a documented partial counts as a successful mapping run.

### Honest findings

Verified pilot run — 2026-11-10:
[run 42823450776](https://github.com/moos-labs/superalgos-runner/actions/runs/42823450776)
— conclusion **success** (all steps success; 168s of script time).
Full record in that run's `results` artifact (`attempt.md` + logs).

- **Commit cloned:** `9f0fb59edd4bae7afa08d06c366e0bcb48103aec`
  (Superalgos `master`, shallow clone, rc 0)
- **Runtime:** Node v20.20.2, npm 10.8.2, Git 2.56.0 on ubuntu-latest
- **`node setup`: rc 0** — `npm ci --omit=optional` added 1575 packages
  (1795 audited) in 33s; husky hooks installed.
- **`node setupPlugins` (no args): rc 0 but a no-op warning** — it does
  not fail, it installs nothing:
  > `[WARN] You need to provide your Github username and token in order for this script to Fork the Plugins repositories into your acccount for you.`
  > `[WARN] Add your user name and token to the parameters of this script and try again please.`
- **`node platform minMemo noBrowser`: rc 124** — i.e. it was still
  running when the 120s window ended, which is the success case here.
  All 11 platform servers reported `Started`, the HTTP interface was
  `Listening at port 34248`, WebSockets at 18041, and the log ends with
  `Superalgos Platform App is Running!` (Platform 1.6.1). It loaded
  **no workspace**: `Initial Workspace ... undefined undefined`.
- **No backtest ran, and none was expected.** The stopping point below
  is the verified one, not a setup failure — setup and headless start
  both work; a backtest does not exist as a headless operation.

Exact stopping point for a headless backtest:

> Blocked at Community Plugins + interactive workspace:
> `node setupPlugins` requires a personal GitHub username + Personal
> Access Token (repo+workflow scopes) and forks/clones plugin repos;
> without it Plugins/ is incomplete. Even with plugins, a backtest is
> not a CLI command — strategies, data-mines and backtesting sessions
> are built/run inside the visual workspace UI, require a workspace
> (project+workspace args), exchange data-mining and, for
> live/exchange data, exchange API keys. No documented headless
> backtest CLI exists in the README.

Known from the README alone, before any run:

- Setup is **not credential-free**: a GitHub Personal Access Token with
  `repo` + `workflow` scopes is listed as a prerequisite, and
  `setupPlugins` cannot complete without a personal username + token.
- Installation expects you to clone **your own fork**, not upstream, so the
  setup scripts can build from multiple repositories under your account.
- There is **no documented headless backtest command**. Backtesting is
  taught through interactive in-app tutorials and done in the visual
  workspace; data-mining and live trading are configured per exchange
  (the tutorial uses Binance / Binance US) inside that workspace.
