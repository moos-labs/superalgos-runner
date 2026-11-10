#!/usr/bin/env bash
# Time-boxed headless attempt for Superalgos (https://github.com/Superalgos/Superalgos)
# Deliverable is an accurate map in results/attempt.md of how far headless
# execution gets. A completed backtest is a bonus, NOT required.
# This script always exits 0 after writing attempt.md (documented partial),
# so partial results are uploaded as a successful mapping run.
set +e
export CI=true
export DEBIAN_FRONTEND=noninteractive

RESULTS="results"
mkdir -p "$RESULTS"
ATTEMPT="$RESULTS/attempt.md"
CLONE_LOG="$RESULTS/clone.log"
SETUP_LOG="$RESULTS/setup.log"
PLUGINS_LOG="$RESULTS/setupPlugins.log"
PLATFORM_LOG="$RESULTS/platform.log"
: > "$CLONE_LOG"; : > "$SETUP_LOG"; : > "$PLUGINS_LOG"; : > "$PLATFORM_LOG"

START_EPOCH=$(date +%s)
NODE_V="$(node -v 2>&1)"
NPM_V="$(npm -v 2>&1)"
GIT_V="$(git --version 2>&1)"
COMMIT="unknown"
CLONE_RC="not-run"
SETUP_RC="not-run"
PLUGINS_RC="not-run"
PLATFORM_RC="not-run"
STOP_POINT="not reached yet"

note() { echo "[attempt] $*"; }

note "node=$NODE_V npm=$NPM_V git=$GIT_V"
df -h . 2>&1 | head -n 5
free -h 2>&1 | head -n 5

# ---- 1. Shallow clone (time-boxed 600s) ----
note "STEP 1: shallow clone Superalgos/Superalgos (master)"
timeout 600 git clone --depth 1 --branch master --single-branch https://github.com/Superalgos/Superalgos.git Superalgos >"$CLONE_LOG" 2>&1
CLONE_RC=$?
cat "$CLONE_LOG"
if [ -d Superalgos/.git ]; then
  COMMIT="$(git -C Superalgos rev-parse HEAD 2>&1)"
  note "cloned commit: $COMMIT"
else
  STOP_POINT="clone failed (rc=$CLONE_RC) - see clone.log"
fi

# Inspect what the cloned README actually documents (follow CURRENT README in-job)
README_EXCERPT=""
if [ -f Superalgos/README.md ]; then
  README_EXCERPT="$(grep -n -E 'node setup|node setupPlugins|node platform|Node\.js|node -v|>= 16|version 20|nvm install' Superalgos/README.md | head -n 60)"
  echo "$README_EXCERPT"
  ls -la Superalgos | head -n 80
  du -sh Superalgos 2>&1
  # List entrypoints that should exist per README
  ls -la Superalgos/setup.js Superalgos/setupPlugins.js Superalgos/platform.js Superalgos/PlatformRoot.js 2>&1
  cat Superalgos/package.json 2>&1 | head -n 80
fi

# ---- 2a. node setup (time-boxed 1200s) ----
if [ -d Superalgos ]; then
  note "STEP 2a: node setup (documented dependency install, no shortcuts/tensorflow)"
  (cd Superalgos && timeout 1200 node setup) >"$SETUP_LOG" 2>&1
  SETUP_RC=$?
  note "node setup rc=$SETUP_RC"
  tail -n 120 "$SETUP_LOG"
else
  SETUP_RC="skipped-no-clone"
fi

# ---- 2b. node setupPlugins (requires GitHub username + PAT per README) ----
# README: node setupPlugins <Your-Github-Username> <Your-Github-Personal-Access-Token>
# It forks every Community Plugins repo into that account and clones into Plugins/.
# No credentials are provided in CI on purpose: run it bare to capture the
# exact missing-prerequisite error, and record the block. Do NOT invent a token.
if [ -d Superalgos ]; then
  note "STEP 2b: node setupPlugins with NO arguments (capturing missing-prerequisite error)"
  (cd Superalgos && timeout 120 node setupPlugins) >"$PLUGINS_LOG" 2>&1
  PLUGINS_RC=$?
  note "node setupPlugins (no args) rc=$PLUGINS_RC"
  cat "$PLUGINS_LOG"
  ls -la Superalgos/Plugins 2>&1 | head -n 40
else
  PLUGINS_RC="skipped-no-clone"
fi

# ---- 3. Headless platform start (time-boxed 120s) ----
# README Usage: node platform minMemo noBrowser
if [ -d Superalgos ]; then
  note "STEP 3: timeout 120 node platform minMemo noBrowser"
  (cd Superalgos && timeout 120 node platform minMemo noBrowser) >"$PLATFORM_LOG" 2>&1
  PLATFORM_RC=$?
  note "platform rc=$PLATFORM_RC (124 = timeout, i.e. it stayed running for the full window)"
  tail -n 200 "$PLATFORM_LOG"
  # Probe any HTTP endpoint the platform may have opened (best-effort, post-exit will fail)
  curl -s -m 5 -o "$RESULTS/platform_http_probe.txt" -w "%{http_code}\n" http://localhost:34248/ 2>&1 | tee "$RESULTS/platform_http_code.txt"
else
  PLATFORM_RC="skipped-no-clone"
fi

END_EPOCH=$(date +%s)
ELAPSED=$((END_EPOCH-START_EPOCH))

# ---- Determine stopping point for a headless backtest ----
if [ ! -d Superalgos ]; then
  STOP_POINT="Blocked at clone (rc=$CLONE_RC). See clone.log."
elif [ "$SETUP_RC" != "0" ] && [ "$SETUP_RC" != "not-run" ]; then
  STOP_POINT="Blocked / incomplete at 'node setup' (rc=$SETUP_RC, 124=timeout after 1200s). See setup.log tail in attempt.md."
else
  STOP_POINT="Blocked at Community Plugins + interactive workspace: 'node setupPlugins' requires a personal GitHub username + Personal Access Token (repo+workflow scopes) and forks/clones plugin repos; without it Plugins/ is incomplete. Even with plugins, a backtest is not a CLI command - strategies, data-mines and backtesting sessions are built/run inside the visual workspace UI (node platform GUI), require a workspace (project+workspace args), exchange data-mining and, for live/exchange data, exchange API keys. No documented headless backtest CLI exists in the README."
fi

# ---- 4. Write results/attempt.md ----
{
  echo "# Superalgos headless attempt"
  echo ""
  echo "- Date (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- Runner: GitHub Actions ubuntu-latest"
  echo "- Node: $NODE_V"
  echo "- npm: $NPM_V"
  echo "- Git: $GIT_V"
  echo "- Superalgos repo cloned: https://github.com/Superalgos/Superalgos (branch master, --depth 1)"
  echo "- Commit cloned: $COMMIT"
  echo "- Elapsed (s): $ELAPSED"
  echo ""
  echo "## Return codes"
  echo ""
  echo "- clone (timeout 600): $CLONE_RC"
  echo "- node setup (timeout 1200): $SETUP_RC"
  echo "- node setupPlugins no-args (timeout 120): $PLUGINS_RC"
  echo "- node platform minMemo noBrowser (timeout 120): $PLATFORM_RC (124 means it was still running when the window ended)"
  echo ""
  echo "## README-documented steps found in the cloned README"
  echo ""
  echo '```'
  echo "$README_EXCERPT"
  echo '```'
  echo ""
  echo "Documented flow (README, Developers/Contributors install):"
  echo "1. Prerequisites: Node.js >= 16 (README example installs Node 20 via nvm), Git, Chrome (browser not needed headless)."
  echo "2. Get a GitHub Personal Access Token (repo + workflow scopes) BEFORE install."
  echo "3. Fork Superalgos, clone YOUR fork (not upstream)."
  echo "4. \`node setup\` - installs Node dependencies."
  echo "5. \`node setupPlugins <Your-Github-Username> <Your-Github-Personal-Access-Token>\` - forks all Community Plugins repos into your account and clones them into Superalgos/Plugins/."
  echo "6. Run: \`node platform [minMemo] [noBrowser] [project] [workspace]\`."
  echo ""
  echo "## How far each step got"
  echo ""
  echo "### Clone log"
  echo '```'
  tail -n 60 "$CLONE_LOG"
  echo '```'
  echo ""
  echo "### node setup - tail of setup.log"
  echo '```'
  tail -n 120 "$SETUP_LOG"
  echo '```'
  echo ""
  echo "### node setupPlugins (no args) - full log"
  echo '```'
  cat "$PLUGINS_LOG"
  echo '```'
  echo ""
  echo "### node platform minMemo noBrowser - tail of platform.log"
  echo '```'
  tail -n 200 "$PLATFORM_LOG"
  echo '```'
  echo ""
  echo "## Exact stopping point for a headless backtest"
  echo ""
  echo "$STOP_POINT"
  echo ""
  echo "Quoted prerequisites / blockers:"
  echo ""
  echo "> README: 'You will need to get an access token from Github.com so that you may authenticate with the service from within the app' and 'Make sure you give it the repo and workflow scopes.'"
  echo ">"
  echo "> README: 'node setupPlugins <Your-Github-Username> <Your-Github-Personal-Access-Token>' - 'This script is going to fork all Community Plugins repositories into your own Github account, and then it will clone each of these repositories into your local Superalgos/Plugins folder.'"
  echo ">"
  echo "> README Usage: 'Once you install and launch the app, a series of interactive tutorials take you by the hand and walk you around the system while you learn the basic skills required to use the interface, mine data, backtest strategies, and even run a live trading session.' Backtesting is presented as a GUI/workspace activity, not a CLI subcommand."
  echo ">"
  echo "> README: 'The tutorial uses Binance or Binance US as the exchange of choice.' Data-mines / exchange access are configured inside the workspace; live sections require an exchange account."
  echo ""
  echo "See run.log, clone.log, setup.log, setupPlugins.log, platform.log in this artifact for full output."
} > "$ATTEMPT"

cat "$ATTEMPT"
note "attempt.md written; elapsed=${ELAPSED}s commit=$COMMIT setup_rc=$SETUP_RC plugins_rc=$PLUGINS_RC platform_rc=$PLATFORM_RC"
exit 0
