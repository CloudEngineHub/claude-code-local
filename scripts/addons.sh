#!/bin/bash
# Claude Code Local — add-ons (macOS)
#
# Each add-on is its own repo with its own one-line installer, so every piece also
# works on its own. This script only picks which ones to run.
#
#   bash scripts/addons.sh menu                      ask which add-ons to install
#   bash scripts/addons.sh install voice,browser     install the named add-ons ("all" for every one)
#   bash scripts/addons.sh uninstall phone [--purge] remove them (--purge also deletes their data)
#   bash scripts/addons.sh list
#
# The menu reads from /dev/tty, so it works under `curl | bash`. With no terminal
# (or KIT_NONINTERACTIVE=1) the menu installs nothing.
#
# CCL_ADDON_SRC=/path/to/folder-of-clones runs each add-on's installer from a local
# checkout instead of GitHub (used for testing).

ADDONS="voice browser phone remote moonstone failover"

addon_repo() {
  case "$1" in
    voice) echo NarrateClaude ;;
    browser) echo browser-agent ;;
    phone) echo claude-screen-to-phone ;;
    remote) echo FiaOS ;;
    moonstone) echo moonstone ;;
    failover) echo claude-failover ;;
  esac
}

addon_desc() {
  case "$1" in
    voice) echo "NarrateClaude: talk to Claude Code hands-free, hear the answers" ;;
    browser) echo "browser-agent: shared-browser broker on 9222 plus the local browser agent (relaunches your browser)" ;;
    phone) echo "claude-screen-to-phone: drive Claude Code from your iPhone over iMessage" ;;
    remote) echo "FiaOS: your Mac's screen and terminal in a browser (asks for a password)" ;;
    moonstone) echo "Moonstone: one window for every Claude Code session (Node 18+)" ;;
    failover) echo "claude-failover: flip agents to this local model when Claude is out" ;;
  esac
}

# Paths inside each repo.
addon_installer() {
  case "$1" in
    browser) echo broker/get.sh ;;
    *) echo install.sh ;;
  esac
}
addon_uninstaller() {
  case "$1" in
    browser) echo broker/uninstall.sh ;;
    *) echo uninstall.sh ;;
  esac
}

# Where each installer clones itself by default (each honours its own env var).
addon_clone_dir() {
  case "$1" in
    voice) echo "${NARRATE_DIR:-$HOME/NarrateClaude}" ;;
    browser)
      if [ -n "$BROWSER_BROKER_DIR" ]; then echo "$BROWSER_BROKER_DIR"
      elif [ ! -d "$HOME/.browser-agent/.git" ] && [ -d "$HOME/.browser-broker/.git" ]; then echo "$HOME/.browser-broker"
      else echo "$HOME/.browser-agent"; fi ;;
    phone) echo "${STP_DIR:-$HOME/claude-screen-to-phone}" ;;
    remote) echo "${FIAOS_DIR:-$HOME/FiaOS}" ;;
    moonstone) echo "${MOONSTONE_DIR:-$HOME/moonstone}" ;;
    failover) echo "${FAILOVER_DIR:-$HOME/.local/share/claude-failover}" ;;
  esac
}

# The env var each installer reads for "clone from here instead of GitHub".
addon_repo_var() {
  case "$1" in
    voice) echo NARRATE_REPO ;;
    browser) echo BROWSER_AGENT_REPO ;;
    phone) echo STP_REPO ;;
    remote) echo FIAOS_REPO ;;
    moonstone) echo MOONSTONE_REPO ;;
    failover) echo FAILOVER_REPO ;;
  esac
}

raw_url() { echo "https://raw.githubusercontent.com/nicedreamzapp/$(addon_repo "$1")/main/$2"; }

# "voice, browser" / "all" / "1 3" -> "voice browser"
normalize_addons() {
  local item out="" n
  for item in $(echo "$*" | tr ',' ' '); do
    item="$(echo "$item" | tr '[:upper:]' '[:lower:]')"
    case "$item" in
      all) echo "$ADDONS"; return 0 ;;
      none|"") ;;
      [1-6]) n=0; for a in $ADDONS; do n=$((n + 1)); [ "$n" = "$item" ] && out="$out $a"; done ;;
      narrate|narrateclaude) out="$out voice" ;;
      fiaos|screen) out="$out remote" ;;
      imessage|iphone) out="$out phone" ;;
      *)
        if [ -n "$(addon_repo "$item")" ]; then out="$out $item"
        else echo "unknown add-on: $item (choose from: $ADDONS, all)" >&2; return 1; fi ;;
    esac
  done
  # de-duplicate, keep menu order
  local final=""
  for a in $ADDONS; do case " $out " in *" $a "*) final="$final $a" ;; esac; done
  echo "${final# }"
}

have_tty() { [ "${KIT_NONINTERACTIVE:-0}" != "1" ] && { : </dev/tty; } 2>/dev/null; }

run_remote_script() {  # $1 add-on, $2 path in repo, rest = args
  local a="$1" path="$2"; shift 2
  local repo; repo="$(addon_repo "$a")"
  if [ -n "$CCL_ADDON_SRC" ] && [ -f "$CCL_ADDON_SRC/$repo/$path" ]; then
    # Fed on stdin, exactly like curl | bash, so the installer clones from the local
    # checkout instead of running in place inside it.
    env "$(addon_repo_var "$a")=$CCL_ADDON_SRC/$repo" bash -s -- "$@" <"$CCL_ADDON_SRC/$repo/$path"
  else
    command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; return 1; }
    curl -fsSL "$(raw_url "$a" "$path")" | bash -s -- "$@"
  fi
}

install_addons() {
  local list ok="" failed="" a
  list="$(normalize_addons "$@")" || return 1
  [ -n "$list" ] || { echo "No add-ons picked."; return 0; }
  for a in $list; do
    echo ""
    echo "── Add-on: $a ($(addon_repo "$a")) ──────────────────────"
    if run_remote_script "$a" "$(addon_installer "$a")"; then ok="$ok $a"; else failed="$failed $a"; fi
  done
  echo ""
  [ -n "$ok" ] && echo "✅ Add-ons installed:$ok"
  if [ -n "$failed" ]; then
    echo "⚠️  Add-ons that did not finish:$failed (re-run: bash $0 install$(echo "$failed" | tr ' ' ','))"
    return 1
  fi
}

uninstall_addons() {
  local purge="" args="" a dir un list
  for a in "$@"; do case "$a" in --purge) purge="--purge" ;; *) args="$args $a" ;; esac; done
  list="$(normalize_addons "$args")" || return 1
  [ -n "$list" ] || { echo "No add-ons named."; return 0; }
  for a in $list; do
    echo ""
    echo "── Removing add-on: $a ($(addon_repo "$a")) ──"
    dir="$(addon_clone_dir "$a")"
    un="$(addon_uninstaller "$a")"
    if [ -f "$dir/$un" ]; then
      bash "$dir/$un" ${purge:+"$purge"} || echo "⚠️  $a uninstall reported a problem"
    else
      run_remote_script "$a" "$un" ${purge:+"$purge"} || echo "⚠️  $a uninstall reported a problem"
    fi
  done
}

menu() {
  if ! have_tty; then
    echo "No terminal to ask on, so no add-ons were installed."
    echo "Add them any time: bash $0 install voice,browser,phone,remote,moonstone,failover  (or: all)"
    return 0
  fi
  echo ""
  echo "Add-ons (each is its own open-source repo, installed with its own one-line installer):"
  local n=0 a
  for a in $ADDONS; do n=$((n + 1)); printf '  %d) %-9s %s\n' "$n" "$a" "$(addon_desc "$a")"; done
  echo ""
  local pick
  printf 'Pick numbers or names (e.g. "1 3" or "voice,phone"), "all", or Enter for none: '
  IFS= read -r pick </dev/tty || pick=""
  [ -n "$pick" ] || { echo "No add-ons. Add them later: bash $0 install <names>"; return 0; }
  install_addons "$pick"
}

case "${1:-}" in
  menu) menu ;;
  install) shift; install_addons "$@" ;;
  uninstall) shift; uninstall_addons "$@" ;;
  list) for a in $ADDONS; do printf '%-9s %s\n' "$a" "$(addon_desc "$a")"; done ;;
  -h|--help|"") sed -n '2,16p' "$0" ;;
  *) echo "usage: bash $0 menu | install <names|all> | uninstall <names|all> [--purge] | list" >&2; exit 1 ;;
esac
