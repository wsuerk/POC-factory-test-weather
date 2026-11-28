#!/usr/bin/env bash
# Factory Manager guard: decides whether an agent in a factory run may write a path.
#
#   bash guard.sh check <path>   decide one path (relative to the repo root, or absolute)
#   bash guard.sh file           decide the path of a Claude Code Edit/Write/MultiEdit/NotebookEdit hook (JSON on stdin)
#   bash guard.sh bash           decide the paths a Claude Code Bash hook's command would change (JSON on stdin),
#                                as far as a reading of the command can tell; the check after every attempt is
#                                the backstop
#
# Allow: exit 0 with no output. Deny: exit 2 with one line on standard error.
#
# The repo root is the folder two levels above this script (<root>/.factory-manager/guardrails/guard.sh), and the
# factory definition is <root>/.factory-manager/factory.yaml.
#
# Environment:
#   FM_RUN_ID, FM_STATION          both set: a factory run at that station; otherwise everything is allowed
#   FM_FROZEN_LIST                 a file of repo-relative paths (one per line) that no station may write
#   FM_WRITE_LIST                  a file of globs (one per line) for maintenance-station and millwright
#   FM_GUARDRAILS_FENCES=off       lifts the fence rules
#   FM_GUARDRAILS_HOLDOUT_TESTS=off  lifts the frozen-file rule
#
# Only bash, coreutils, sed, awk and grep are used, as Git for Windows ships them.

mode=${1:-}

drain() {
  cat >/dev/null 2>&1 || true
}

deny() {
  printf '%s\n' "$1" >&2
  exit 2
}

# Outside a factory run everything is allowed.
if [[ -z ${FM_RUN_ID:-} || -z ${FM_STATION:-} ]]; then
  [[ $mode == file || $mode == bash ]] && drain
  exit 0
fi

station=$FM_STATION
fences=on
holdout=on
[[ ${FM_GUARDRAILS_FENCES:-} == off ]] && fences=off
[[ ${FM_GUARDRAILS_HOLDOUT_TESTS:-} == off ]] && holdout=off
if [[ $fences == off && $holdout == off ]]; then
  [[ $mode == file || $mode == bash ]] && drain
  exit 0
fi

case ${OSTYPE:-} in
  msys* | cygwin* | win*) fold_case=1 ;;
  *) fold_case=0 ;;
esac

# ---- paths ----

UPPER=ABCDEFGHIJKLMNOPQRSTUVWXYZ
LOWER=abcdefghijklmnopqrstuvwxyz

# $1 with forward slashes, and a drive path D:/a as /d/a. Sets REPLY.
to_posix() {
  local p=${1//\\//} d pre
  if [[ $p =~ ^([A-Za-z]):(/.*)?$ ]]; then
    d=${BASH_REMATCH[1]}
    pre=${UPPER%%"$d"*}
    if ((${#pre} < 26)); then
      d=${LOWER:${#pre}:1}
    fi
    p="/$d${BASH_REMATCH[2]}"
  fi
  REPLY=$p
}

# $1 made absolute against the folder $2, with . and .. resolved. Sets REPLY.
canon() {
  to_posix "$1"
  local p=$REPLY rest seg out=""
  [[ $p == /* ]] || p="$2/$p"
  rest=$p
  while [[ -n $rest ]]; do
    seg=${rest%%/*}
    if [[ $rest == */* ]]; then
      rest=${rest#*/}
    else
      rest=""
    fi
    case $seg in
      '' | .) ;;
      ..) out=${out%/*} ;;
      *) out+="/$seg" ;;
    esac
  done
  REPLY=${out:-/}
}

# The repo-relative form of the canonical path $1 in REPLY; fails when $1 is outside the repo.
relative() {
  local p=$1 r=$root pc rc
  pc=$p
  rc=$r
  if ((fold_case)); then
    pc=${p,,}
    rc=${r,,}
  fi
  if [[ $pc == "$rc" ]]; then
    REPLY=""
    return 0
  fi
  if [[ $rc == / ]]; then
    REPLY=${p#/}
    return 0
  fi
  if [[ $pc == "$rc"/* ]]; then
    REPLY=${p:${#r}+1}
    return 0
  fi
  return 1
}

to_posix "$PWD"
here=$REPLY
canon "${BASH_SOURCE[0]:-$0}" "$here"
root=${REPLY%/*}
root=${root%/*}
root=${root%/*}
[[ -n $root ]] || root=/

# ---- globs, as the app's fence check reads them ----

# The anchored regular expression for the glob $1. Sets REPLY.
glob_re() {
  local g=$1 re='^' c i n=${#1}
  for ((i = 0; i < n; i++)); do
    c=${g:i:1}
    if [[ $c == '*' ]]; then
      if [[ ${g:i+1:1} == '*' ]]; then
        if [[ ${g:i+2:1} == / ]]; then
          re+='(.*/)?'
          ((i += 2))
        else
          re+='.*'
          ((i += 1))
        fi
      else
        re+='[^/]*'
      fi
    elif [[ $c == '?' ]]; then
      re+='[^/]'
    elif [[ $c == '^' ]]; then
      re+='\^'
    elif [[ '.+${}()|[]\' == *"$c"* ]]; then
      re+="[$c]"
    else
      re+=$c
    fi
  done
  REPLY="$re\$"
}

trim() {
  local s=$1
  s=${s%$'\r'}
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  REPLY=$s
}

# ---- the factory definition ----

AWK_COMMON='
function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
function repl(s, a, b,   out, i) {
  out = ""
  while ((i = index(s, a)) > 0) { out = out substr(s, 1, i - 1) b; s = substr(s, i + length(a)) }
  return out s
}
'

YAML_AWK='
function unq(s,   q) {
  s = trim(s); q = substr(s, 1, 1)
  if (length(s) >= 2 && q == "\047" && substr(s, length(s), 1) == q) return repl(substr(s, 2, length(s) - 2), "\047\047", "\047")
  if (length(s) >= 2 && q == "\"" && substr(s, length(s), 1) == q) {
    s = substr(s, 2, length(s) - 2); s = repl(s, "\\\\", "\001"); s = repl(s, "\\\"", "\""); return repl(s, "\001", "\\")
  }
  return s
}
function nocomment(s,   i, c, q) {
  q = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (q != "") { if (c == q) q = ""; continue }
    if (c == "\047" || c == "\"") { q = c; continue }
    if (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t]/)) return substr(s, 1, i - 1)
  }
  return s
}
function depth(s,   i, c, q, d) {
  q = ""; d = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (q != "") { if (c == q) q = ""; continue }
    if (c == "\047" || c == "\"") { q = c; continue }
    if (c == "[" || c == "{") d++
    if (c == "]" || c == "}") d--
  }
  return d
}
function splitflow(s, parts,   i, c, q, d, n, cur) {
  n = 0; cur = ""; q = ""; d = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (q != "") { cur = cur c; if (c == q) q = ""; continue }
    if (c == "\047" || c == "\"") { q = c; cur = cur c; continue }
    if (c == "[" || c == "{") d++
    if (c == "]" || c == "}") d--
    if (c == "," && d == 0) { if (trim(cur) != "") parts[++n] = trim(cur); cur = ""; continue }
    cur = cur c
  }
  if (trim(cur) != "") parts[++n] = trim(cur)
  return n
}
function inner(s) { s = trim(s); return substr(s, 2, length(s) - 2) }
function colon(s,   i, c, q) {
  q = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (q != "") { if (c == q) q = ""; continue }
    if (c == "\047" || c == "\"") { q = c; continue }
    if (c == ":" && (i == length(s) || substr(s, i + 1, 1) ~ /[ \t]/)) return i
  }
  return 0
}
function emitlist(kind, zone, v,   parts, n, i) {
  v = trim(v)
  if (v == "") return
  if (substr(v, 1, 1) == "[") {
    n = splitflow(inner(v), parts)
    for (i = 1; i <= n; i++) print kind "\t" zone "\t" unq(parts[i])
  } else print kind "\t" zone "\t" unq(v)
}
function emitzone(zone, v,   parts, n, i, c, k) {
  v = trim(v)
  if (substr(v, 1, 1) == "{") {
    n = splitflow(inner(v), parts)
    for (i = 1; i <= n; i++) {
      c = colon(parts[i]); if (!c) continue
      k = unq(substr(parts[i], 1, c - 1))
      if (k == "include") emitlist("I", zone, substr(parts[i], c + 1))
      else if (k == "exclude") emitlist("E", zone, substr(parts[i], c + 1))
    }
  } else emitlist("I", zone, v)
}
function addfence(v,   parts, n, i, c) {
  v = trim(v)
  if (substr(v, 1, 1) == "{") v = inner(v)
  n = splitflow(v, parts)
  for (i = 1; i <= n; i++) {
    c = colon(parts[i]); if (!c) continue
    nf++; fz[nf] = unq(substr(parts[i], 1, c - 1)); fa[nf] = unq(substr(parts[i], c + 1))
  }
}
function flowitem(v,   parts, n, i, c, k) {
  n = splitflow(inner(v), parts)
  for (i = 1; i <= n; i++) {
    c = colon(parts[i]); if (!c) continue
    k = unq(substr(parts[i], 1, c - 1))
    if (k == "id") sid = unq(substr(parts[i], c + 1))
    else if (k == "fence") addfence(substr(parts[i], c + 1))
  }
}
function flush(   i) {
  if (sid != "" && sid == st) { print "S\t" sid; for (i = 1; i <= nf; i++) print "F\t" fz[i] "\t" fa[i] }
  sid = ""; nf = 0
}
function handle(target, v) {
  if (target == "zone") emitzone(curzone, v)
  else if (target == "I" || target == "E") emitlist(target, curzone, v)
  else if (target == "fence") addfence(v)
  else if (target == "item") flowitem(v)
}
function start(target, v) {
  if (depth(v) > 0) { acc = v; acct = target } else handle(target, v)
}
function stationkv(t,   c, k, v) {
  c = colon(t); if (!c) return
  k = unq(substr(t, 1, c - 1)); v = trim(substr(t, c + 1))
  if (k == "id") sid = unq(v)
  else if (k == "fence") { if (v == "") infence = 1; else start("fence", v) }
}
function zoneline(   c, k, v, f) {
  if (zind < 0) zind = ind
  if (ind <= zind) {
    c = colon(t); if (!c) return
    curzone = unq(substr(t, 1, c - 1)); zsub = "I"; v = trim(substr(t, c + 1))
    if (v != "") start("zone", v)
    return
  }
  f = substr(t, 1, 1)
  if (f == "-") { emitlist(zsub, curzone, substr(t, 2)); return }
  if (f == "[" || f == "{") { start(zsub == "E" ? "E" : "zone", t); return }
  c = colon(t); if (!c) return
  k = unq(substr(t, 1, c - 1)); v = trim(substr(t, c + 1))
  if (k == "include") zsub = "I"; else if (k == "exclude") zsub = "E"; else return
  if (v != "") start(zsub, v)
}
function stationline(   rest, tmp) {
  if (substr(t, 1, 1) == "-" && (sind < 0 || ind <= sind)) {
    flush(); sind = ind; infence = 0
    tmp = substr(t, 2); match(tmp, /^[ ]*/); rest = trim(tmp)
    if (rest == "") { kind = -1; return }
    kind = ind + 1 + RLENGTH
    if (substr(rest, 1, 1) == "{") start("item", rest); else stationkv(rest)
    return
  }
  if (sind < 0 || ind <= sind) return
  if (kind < 0) kind = ind
  if (infence && ind > kind) {
    if (substr(t, 1, 1) == "{") start("fence", t); else addfence(t)
    return
  }
  infence = 0
  if (ind == kind) stationkv(t)
}
BEGIN { zind = -1; sind = -1; kind = -1; acc = ""; sect = "" }
{
  line = $0; sub(/\r$/, "", line); line = nocomment(line)
  if (line ~ /^[ \t]*$/) next
  if (acc != "") {
    acc = acc " " line
    if (depth(acc) <= 0) { v = acc; acc = ""; handle(acct, v) }
    next
  }
  match(line, /^[ ]*/); ind = RLENGTH; t = trim(substr(line, ind + 1))
  if (t == "---" || t == "...") next
  if (ind == 0 && substr(t, 1, 1) != "-") {
    if (sect == "stations") flush()
    c = colon(t); sect = c ? unq(substr(t, 1, c - 1)) : ""
    zind = -1; sind = -1; kind = -1; infence = 0
    next
  }
  if (sect == "zones") zoneline()
  else if (sect == "stations") stationline()
}
END {
  if (acc != "") handle(acct, acc)
  if (sect == "stations") flush()
}
'

JSON_AWK='
function hexval(h,   i, v, c) {
  v = 0; h = tolower(h)
  for (i = 1; i <= length(h); i++) { c = index("0123456789abcdef", substr(h, i, 1)); if (!c) return -1; v = v * 16 + c - 1 }
  return v
}
function utf8(n) {
  if (n < 128) return sprintf("%c", n)
  if (n < 2048) return sprintf("%c%c", 192 + int(n / 64), 128 + n % 64)
  return sprintf("%c%c%c", 224 + int(n / 4096), 128 + int(n / 64) % 64, 128 + n % 64)
}
function unesc(t,   out, i, c, v) {
  out = ""
  while ((i = index(t, "\\")) > 0) {
    out = out substr(t, 1, i - 1); c = substr(t, i + 1, 1)
    if (c == "u") { v = hexval(substr(t, i + 2, 4)); if (v > 0) out = out utf8(v); t = substr(t, i + 6); continue }
    if (c == "n") out = out "\n"
    else if (c == "t") out = out "\t"
    else if (c == "r") out = out "\r"
    else if (c != "b" && c != "f") out = out c
    t = substr(t, i + 2)
  }
  out = out t
  out = repl(out, "\001B", "\\")
  return repl(out, "\001Q", "\"")
}
{ s = s $0 "\n" }
END {
  s = repl(s, "\\\\", "\001B"); s = repl(s, "\\\"", "\001Q")
  d = 0
  while (match(s, /"[^"]*"|[][{}:,]|[^][ \t\r\n{}:,"]+/)) {
    tok = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
    c = substr(tok, 1, 1)
    if (c == "{" || c == "[") { d++; ty[d] = c; ek[d] = (c == "{"); ky[d] = ""; continue }
    if (c == "}" || c == "]") { if (d > 0) d--; continue }
    if (c == ":") { ek[d] = 0; continue }
    if (c == ",") { if (ty[d] == "{") ek[d] = 1; continue }
    if (ty[d] == "{" && ek[d]) { ky[d] = (c == "\"") ? unesc(substr(tok, 2, length(tok) - 2)) : tok; continue }
    if (c != "\"") continue
    if (d == 1 && ty[1] == "{") {
      if (ky[1] == "tool_name") tool = unesc(substr(tok, 2, length(tok) - 2))
      else if (ky[1] == "cwd") cwd = unesc(substr(tok, 2, length(tok) - 2))
    } else if (d == 2 && ty[1] == "{" && ty[2] == "{" && ky[1] == "tool_input") {
      if (ky[2] == "file_path") fp = unesc(substr(tok, 2, length(tok) - 2))
      else if (ky[2] == "notebook_path") nb = unesc(substr(tok, 2, length(tok) - 2))
      else if (ky[2] == "command") cmd = unesc(substr(tok, 2, length(tok) - 2))
    }
  }
  printf "%s\037%s\037%s\037%s\037%s", tool, fp, nb, cwd, cmd
}
'

known=0
zones=()
rk=()
rz=()
rr=()
fz=()
fa=()

load_definition() {
  local out k a b z seen
  out=$(LC_ALL=C awk -v st="$station" "$AWK_COMMON$YAML_AWK" "$root/.factory-manager/factory.yaml" 2>/dev/null)
  while IFS=$'\t' read -r k a b; do
    case $k in
      S) known=1 ;;
      F)
        fz+=("$a")
        fa+=("$b")
        ;;
      I | E)
        glob_re "$b"
        rk+=("$k")
        rz+=("$a")
        rr+=("$REPLY")
        seen=0
        for z in "${zones[@]}"; do
          if [[ $z == "$a" ]]; then
            seen=1
            break
          fi
        done
        ((seen)) || zones+=("$a")
        ;;
    esac
  done <<<"$out"
}

# Whether the zone $1 owns $rel: one of its include globs matches and none of its exclude globs.
in_zone() {
  local i inc=0
  for i in "${!rk[@]}"; do
    [[ ${rz[i]} == "$1" ]] || continue
    if [[ $rel =~ ${rr[i]} ]]; then
      [[ ${rk[i]} == E ]] && return 1
      inc=1
    fi
  done
  ((inc))
}

in_factory() {
  case $rel in
    .factory-manager | .factory-manager/* | .claude | .claude/*) return 0 ;;
  esac
  in_zone factory
}

# The first zone (in definition order) that owns $rel, or none. Sets REPLY.
owner() {
  local z
  for z in "${zones[@]}"; do
    [[ $z == factory ]] && continue
    if in_zone "$z"; then
      REPLY=$z
      return
    fi
  done
  REPLY=none
}

# The station's access to the zone $1. Sets REPLY.
access() {
  local i
  REPLY=""
  for i in "${!fz[@]}"; do
    if [[ ${fz[i]} == "$1" ]]; then
      REPLY=${fa[i]}
      return
    fi
  done
}

# Whether $rel matches a glob in the list file $1.
list_matches() {
  local f=$1 line
  [[ -n $f && -r $f ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    trim "$line"
    line=$REPLY
    [[ -z $line || $line == \#* ]] && continue
    line=${line//\\//}
    line=${line#./}
    glob_re "$line"
    [[ $rel =~ $REPLY ]] && return 0
  done <"$f"
  return 1
}

is_frozen() {
  local f=${FM_FROZEN_LIST:-} line
  [[ -n $f && -r $f ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    trim "$line"
    line=$REPLY
    [[ -z $line ]] && continue
    canon "$line" "$root"
    relative "$REPLY" || continue
    [[ $REPLY == "$rel" ]] && return 0
  done <"$f"
  return 1
}

factory_reason() {
  REPLY="$1 is in the factory zone, which no station may change. If it must change, finish with a maintenanceRequest saying why."
}

fence_reason() {
  owner
  REPLY="$1 is outside the $station station's fence (zone $REPLY). Don't write it: if it must change, finish with a maintenanceRequest saying why."
}

loaded=0
# When 1, the path being decided is a folder, and is matched against the globs as <path>/.
as_dir=0

# Decides the path $2 (shown as $1), taken from the folder $3 when relative. Returns 0 when it may be written;
# otherwise returns 1 with the deny text in REPLY.
judge() {
  local disp=$1 inside=1 factory=0
  canon "$2" "$3"
  if relative "$REPLY"; then
    rel=$REPLY
  else
    inside=0
    rel=""
  fi
  if [[ $holdout == on && $inside == 1 ]] && is_frozen; then
    REPLY="$disp is a frozen holdout test. Don't change it: to change it, finish with a maintenanceRequest (kind scenario-change) saying why."
    return 1
  fi
  [[ $fences == off ]] && return 0
  if ((!inside)); then
    REPLY="$disp is outside the repo."
    return 1
  fi
  ((as_dir)) && rel+=/
  if ((!loaded)); then
    load_definition
    loaded=1
  fi
  in_factory && factory=1
  case $station in
    maintenance-station)
      if ((factory)); then
        factory_reason "$disp"
        return 1
      fi
      list_matches "${FM_WRITE_LIST:-}" && return 0
      fence_reason "$disp"
      return 1
      ;;
    millwright)
      ((factory)) && return 0
      list_matches "${FM_WRITE_LIST:-}" && return 0
      fence_reason "$disp"
      return 1
      ;;
    *)
      if ((!known)); then
        REPLY="The station $station isn't in the factory definition, so it may write nothing."
        return 1
      fi
      if ((factory)); then
        factory_reason "$disp"
        return 1
      fi
      owner
      if [[ $REPLY != none ]]; then
        access "$REPLY"
        [[ $REPLY == write ]] && return 0
      fi
      fence_reason "$disp"
      return 1
      ;;
  esac
}

# Decides the path $2 (shown as $1), taken from the folder $3 when relative. Exits.
decide() {
  judge "$@" || deny "$REPLY"
  exit 0
}

# Splits the hook fields the JSON reader printed ($1) into tool, file_path, notebook_path, cwd and command.
split_hook() {
  local rest=$1 sep=$'\037'
  tool=${rest%%"$sep"*}
  rest=${rest#*"$sep"}
  file_path=${rest%%"$sep"*}
  rest=${rest#*"$sep"}
  notebook_path=${rest%%"$sep"*}
  rest=${rest#*"$sep"}
  cwd=${rest%%"$sep"*}
  command=${rest#*"$sep"}
}

# ---- reading a Bash command (best effort: the check after every attempt is the backstop) ----

SEP=$'\003'    # ends a command
OUT=$'\004>'   # an output redirection: the next word is written
DUP=$'\004>&'  # >&: the next word is a descriptor, or a file that is written
INP=$'\004<'   # an input redirection or here-string: the next word is read
HERE=$'\004<<' # a here-document: the next word is its delimiter
DYN=$'\002'    # marks a word with an expansion ($ or `), whose value can't be told

TOK=()
hds=()
w=""
has=0
quoted=0
dyn=0
want_hd=0

end_word() {
  if ((has)); then
    if ((want_hd)); then
      hds+=("$w")
      want_hd=0
    fi
    if ((dyn)); then
      TOK+=("$DYN$w")
    else
      TOK+=("$w")
    fi
  fi
  w=""
  has=0
  quoted=0
  dyn=0
}

# Splits the command line $1 into TOK: words (quotes removed), redirection operators and command separators.
tokenize() {
  local s=$1 n=${#1} i c nx q="" d line
  TOK=()
  hds=()
  w=""
  has=0
  quoted=0
  dyn=0
  want_hd=0
  for ((i = 0; i < n; i++)); do
    c=${s:i:1}
    if [[ $q == "'" ]]; then
      if [[ $c == "'" ]]; then
        q=""
      else
        w+=$c
      fi
      continue
    fi
    if [[ $q == '"' ]]; then
      if [[ $c == '"' ]]; then
        q=""
      elif [[ $c == '\' ]]; then
        nx=${s:i+1:1}
        case $nx in
          '"' | '\' | '$' | '`')
            w+=$nx
            ((i++))
            ;;
          $'\n') ((i++)) ;;
          *) w+=$c ;;
        esac
      else
        [[ $c == '$' || $c == '`' ]] && dyn=1
        w+=$c
      fi
      continue
    fi
    nx=${s:i+1:1}
    case $c in
      ' ' | $'\t' | $'\r') end_word ;;
      "'" | '"')
        q=$c
        has=1
        quoted=1
        ;;
      '\')
        ((i++))
        if [[ -n $nx && $nx != $'\n' ]]; then
          w+=$nx
          has=1
          quoted=1
        fi
        ;;
      ';' | $'\n')
        end_word
        TOK+=("$SEP")
        if [[ $c == $'\n' ]]; then
          # Skip the bodies of the here-documents opened on this line.
          for d in "${hds[@]}"; do
            while ((i + 1 < n)); do
              line=${s:i+1}
              line=${line%%$'\n'*}
              ((i += ${#line} + 1))
              line=${line#"${line%%[!$'\t']*}"}
              line=${line%$'\r'}
              [[ $line == "$d" ]] && break
            done
          done
          hds=()
        fi
        ;;
      '|')
        end_word
        [[ $nx == '|' || $nx == '&' ]] && ((i++))
        TOK+=("$SEP")
        ;;
      '&')
        end_word
        if [[ $nx == '&' ]]; then
          ((i++))
          TOK+=("$SEP")
        elif [[ $nx == '>' ]]; then
          ((i++))
          [[ ${s:i+1:1} == '>' ]] && ((i++))
          TOK+=("$OUT")
        else
          TOK+=("$SEP")
        fi
        ;;
      '>' | '<')
        # A descriptor number joined to the operator (2>) belongs to it.
        if ((has && !quoted && !dyn)) && [[ $w =~ ^[0-9]+$ ]]; then
          w=""
          has=0
        else
          end_word
        fi
        if [[ $c == '>' ]]; then
          case $nx in
            '>' | '|')
              ((i++))
              TOK+=("$OUT")
              ;;
            '&')
              ((i++))
              TOK+=("$DUP")
              ;;
            *) TOK+=("$OUT") ;;
          esac
        else
          case $nx in
            '<')
              ((i++))
              if [[ ${s:i+1:1} == '<' ]]; then
                ((i++))
                TOK+=("$INP")
              else
                [[ ${s:i+1:1} == '-' ]] && ((i++))
                TOK+=("$HERE")
                want_hd=1
              fi
              ;;
            '>')
              ((i++))
              TOK+=("$OUT")
              ;;
            '&')
              ((i++))
              TOK+=("$INP")
              ;;
            *) TOK+=("$INP") ;;
          esac
        fi
        ;;
      '#')
        if ((has)); then
          w+=$c
        else
          line=${s:i}
          line=${line%%$'\n'*}
          ((i += ${#line} - 1))
        fi
        ;;
      '$' | '`')
        dyn=1
        has=1
        w+=$c
        ;;
      *)
        w+=$c
        has=1
        ;;
    esac
  done
  end_word
}

ARGS=()
SEEN=" "
declare -A OV=()

# Reads the arguments $4... of a command: short options in $1 take a value (joined or the next word), short options
# in $2 take the rest of their word as an optional value, and the long options in $3 (space-separated) take the next
# word when not joined with =. Sets ARGS (the other arguments), SEEN (the options seen) and OV (their values).
parse_args() {
  local sv=$1 so=$2 lv=$3 word rest ch name val ddash=0
  shift 3
  ARGS=()
  SEEN=" "
  OV=()
  while (($#)); do
    word=$1
    shift
    if ((ddash)) || [[ $word != -?* ]]; then
      ARGS+=("$word")
      continue
    fi
    if [[ $word == -- ]]; then
      ddash=1
      continue
    fi
    if [[ $word == --* ]]; then
      name=${word#--}
      val=""
      if [[ $name == *=* ]]; then
        val=${name#*=}
        name=${name%%=*}
      elif [[ " $lv " == *" $name "* ]] && (($#)); then
        val=$1
        shift
      fi
      SEEN+="$name "
      OV[$name]=$val
      continue
    fi
    rest=${word#-}
    while [[ -n $rest ]]; do
      ch=${rest:0:1}
      rest=${rest:1}
      SEEN+="$ch "
      if [[ $sv == *"$ch"* ]]; then
        if [[ -n $rest ]]; then
          OV[$ch]=$rest
        elif (($#)); then
          OV[$ch]=$1
          shift
        fi
        break
      elif [[ $so == *"$ch"* ]]; then
        OV[$ch]=$rest
        break
      fi
    done
  done
}

# Whether parse_args saw one of the options $@.
seen() {
  local o
  for o in "$@"; do
    [[ $SEEN == *" $o "* ]] && return 0
  done
  return 1
}

# Whether the word $1, taken from the folder $2, names an existing folder.
is_folder() {
  [[ $1 == "$DYN"* ]] && return 1
  canon "$1" "$2"
  [[ -d $REPLY ]]
}

# The targets of cp with the arguments $@: the destination, or <folder>/<source's file name> for a folder.
cp_targets() {
  parse_args "tS" "" "target-directory suffix" "$@"
  local dir=${OV[t]:-${OV[target-directory]:-}} dest s
  local -a srcs=("${ARGS[@]}")
  if [[ -z $dir ]]; then
    ((${#srcs[@]} >= 2)) || return 0
    dest=${srcs[${#srcs[@]} - 1]}
    srcs=("${srcs[@]:0:${#srcs[@]}-1}")
    if [[ $dest != */ ]] && ! is_folder "$dest" "$tb"; then
      targets+=("$dest")
      return 0
    fi
    dir=$dest
  fi
  for s in "${srcs[@]}"; do
    if [[ $s == "$DYN"* || $dir == "$DYN"* ]]; then
      targets+=("$DYN")
      continue
    fi
    while [[ $s == */ && $s != / ]]; do s=${s%/}; done
    targets+=("${dir%/}/${s##*/}")
  done
}

# The targets of git with the arguments $@. Follows -C into tb.
git_targets() {
  local -a g=("$@")
  local sub x on=0
  while ((${#g[@]})) && [[ ${g[0]} == -* ]]; do
    case ${g[0]} in
      -C)
        [[ ${g[1]:-} == "$DYN"* ]] && return 0
        canon "${g[1]:-.}" "$tb"
        tb=$REPLY
        g=("${g[@]:2}")
        ;;
      -c | --git-dir | --work-tree | --namespace) g=("${g[@]:2}") ;;
      *) g=("${g[@]:1}") ;;
    esac
  done
  sub=${g[0]:-}
  g=("${g[@]:1}")
  case $sub in
    rm | mv)
      parse_args "" "" "pathspec-from-file" "${g[@]}"
      targets+=("${ARGS[@]}")
      ;;
    restore)
      parse_args "s" "" "source pathspec-from-file" "${g[@]}"
      targets+=("${ARGS[@]}")
      ;;
    checkout)
      for x in "${g[@]}"; do
        if ((on)); then
          targets+=("$x")
        elif [[ $x == -- ]]; then
          on=1
        fi
      done
      ;;
  esac
}

# Whether git ignores the repo-relative path $1.
git_ignored() {
  (
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
    cd "$root" 2>/dev/null || exit 1
    git check-ignore -q -- "$1"
  ) >/dev/null 2>&1
}

# Decides the target $1 of a command, taken from the folder $2; denies (exits) when it may not be written.
check_target() {
  local t=$1 b=$2 abs d reason
  [[ -z $t || $t == "$DYN"* || $t == '&'* || $t == '('* || $t == /dev/* ]] && return 0
  [[ $t == '~' || $t == '~/'* ]] && t=${HOME:-}${t:1}
  canon "$t" "$b"
  abs=$REPLY
  relative "$abs" || return 0
  d=${REPLY:-.}
  as_dir=0
  [[ -d $abs ]] && as_dir=1
  if ! judge "$d" "$abs" /; then
    reason=$REPLY
    git_ignored "$d" && return 0
    deny "This command would change $d: $reason"
  fi
  return 0
}

# Decides one command: WORDS (its words) and REDS (the targets of its output redirections), from the folder base.
# Follows cd to a literal folder.
evaluate() {
  local -a w=("${WORDS[@]}") targets=()
  local name="" tb=$base t to
  while ((${#w[@]})); do
    case ${w[0]} in
      [A-Za-z_]*=*)
        if [[ ${w[0]%%=*} =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
          w=("${w[@]:1}")
          continue
        fi
        ;;
      sudo | command | nohup | time | exec | builtin | env)
        w=("${w[@]:1}")
        while ((${#w[@]})) && [[ ${w[0]} == -* ]]; do w=("${w[@]:1}"); done
        continue
        ;;
    esac
    break
  done
  if ((${#w[@]})); then
    name=${w[0]##*/}
    case $name in
      rm | tee)
        parse_args "" "" "" "${w[@]:1}"
        targets=("${ARGS[@]}")
        ;;
      touch)
        parse_args "dtr" "" "date time reference" "${w[@]:1}"
        targets=("${ARGS[@]}")
        ;;
      truncate)
        parse_args "sr" "" "size reference" "${w[@]:1}"
        targets=("${ARGS[@]}")
        ;;
      mv)
        parse_args "tS" "" "target-directory suffix" "${w[@]:1}"
        targets=("${ARGS[@]}")
        [[ -n ${OV[t]:-} ]] && targets+=("${OV[t]}")
        [[ -n ${OV[target-directory]:-} ]] && targets+=("${OV[target-directory]}")
        ;;
      cp) cp_targets "${w[@]:1}" ;;
      sed)
        parse_args "efl" "i" "expression file line-length" "${w[@]:1}"
        if seen i in-place; then
          if seen e f expression file; then
            targets=("${ARGS[@]}")
          else
            targets=("${ARGS[@]:1}")
          fi
        fi
        ;;
      perl)
        parse_args "eE" "iIMmlx0CdD" "" "${w[@]:1}"
        if seen i; then
          if seen e E; then
            targets=("${ARGS[@]}")
          else
            targets=("${ARGS[@]:1}")
          fi
        fi
        ;;
      git) git_targets "${w[@]:1}" ;;
    esac
  fi
  for t in "${targets[@]}"; do
    check_target "$t" "$tb"
  done
  for t in "${REDS[@]}"; do
    check_target "$t" "$base"
  done
  if [[ $name == cd || $name == pushd ]]; then
    parse_args "" "" "" "${w[@]:1}"
    to=${ARGS[0]:-}
    if [[ -n $to && $to != "$DYN"* && $to != - && $to != *[\*\?\[]* ]]; then
      [[ $to == '~' || $to == '~/'* ]] && to=${HOME:-}${to:1}
      canon "$to" "$base"
      base=$REPLY
    fi
  fi
}

# Decides every command in TOK, in order.
run_commands() {
  local count=${#TOK[@]} k=0 t nx
  WORDS=()
  REDS=()
  while ((k <= count)); do
    if ((k == count)); then
      t=$SEP
    else
      t=${TOK[k]}
    fi
    if [[ $t == "$SEP" ]]; then
      ((${#WORDS[@]} || ${#REDS[@]})) && evaluate
      WORDS=()
      REDS=()
    elif [[ $t == $'\004'* ]]; then
      nx=""
      if ((k + 1 < count)) && [[ ${TOK[k + 1]} != $'\004'* && ${TOK[k + 1]} != "$SEP" ]]; then
        nx=${TOK[k + 1]}
        ((k++))
      fi
      if [[ $t == "$OUT" ]]; then
        REDS+=("$nx")
      elif [[ $t == "$DUP" && ! $nx =~ ^[0-9]*-?$ ]]; then
        REDS+=("$nx")
      fi
    else
      WORDS+=("$t")
    fi
    ((k++))
  done
}

case $mode in
  check)
    [[ -n ${2:-} ]] || exit 0
    decide "$2" "$2" "$root"
    ;;
  bash)
    split_hook "$(LC_ALL=C awk "$AWK_COMMON$JSON_AWK")"
    [[ -n $command ]] || exit 0
    base=$root
    if [[ -n $cwd ]]; then
      canon "$cwd" "$root"
      base=$REPLY
    fi
    tokenize "$command"
    run_commands
    exit 0
    ;;
  file)
    split_hook "$(LC_ALL=C awk "$AWK_COMMON$JSON_AWK")"
    path=$file_path
    [[ $tool == NotebookEdit ]] && path=$notebook_path
    [[ -n $path ]] || path=${file_path:-$notebook_path}
    [[ -n $path ]] || exit 0
    base=$root
    if [[ -n $cwd ]]; then
      canon "$cwd" "$root"
      base=$REPLY
    fi
    decide "$path" "$path" "$base"
    ;;
  *)
    deny "guard.sh: unknown mode '$mode'; use check, file or bash."
    ;;
esac
exit 0
