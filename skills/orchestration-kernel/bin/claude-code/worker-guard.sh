#!/bin/bash
# PreToolUse guard for the kernel's write-nothing `worker` agent.
#
# A write-nothing executor runs discovery, review fan-out and re-verification;
# the kernel's executor contract bars it from writing any repository and any
# workspace layer. One
# scoped exception: writes beneath the session scratchpad and
# beneath a repository's gitignored tmp/ are permitted, so probe-style
# verification units can build sandboxes. The worker deletes what it creates
# there before handback; the orchestrator sweeps survivors at ingest and at
# engagement conclusion.
#
# Containment has two layers. The file-tool path rule below is one; the Bash
# layer is an ALLOWLIST, deny-by-default. Three adversarial review rounds each
# defeated the earlier regex blocklist with a new parse trick, and the human
# ruled the inversion: shell cannot be reliably parsed with regexes, so the
# guard stopped recognising writes and recognises safe reads instead. A
# command is split on every separator that can chain or substitute a second
# command — `;`, `&`, `|`, `(`, `)`, backtick and newline — and each fragment
# must independently match a recognised read-only shape, or be provably
# scratch-confined (every judged path resolving beneath the decision-160
# allowance). Anything else is denied. Quote-aware parsing is deliberately
# absent: a separator inside quotes severs the command at that point, and a
# severed fragment fails the allowlist — so quoting tricks over-deny rather
# than escape, at the cost of denying legitimate patterns that carry shell
# metacharacters inside quotes: regex alternation, multi-command sed scripts,
# pipes inside a quoted jq filter (`jq '.a | .b'`), a quoted `|` field
# separator for awk (`awk -F'|'`). Each severs and denies; hand the need back.
#
# Guaranteed: a Bash command is denied unless every fragment is recognised
# safe. Accepted risks, both outside what command text can show: a malicious
# binary shadowing an allowlisted name on PATH, and code execution through the
# hooks of a git repository the worker built in scratch — the hook files live
# inside the allowance, but the process they start is not confined by this
# guard. The guard judges the text of the tool call, not the processes it
# becomes.
#
# Traversal handling: any `..` component in a judged path is denied outright —
# the harness resolves paths component-wise, so a symlink followed by `..` can
# escape a lexical collapse, and no legitimate worker write needs `..`. A leaf
# that is itself a symlink, or an existing file with a hardlink count above
# one, is denied on every judged write target — file tools and Bash alike:
# both alias a file outside the judged location. The leaf check is what
# holds when a link is planted anyway: `ln` operands must resolve beneath the
# allowance and `cp`'s link-creating flags are denied, but a link-preserving
# copy (`cp -r` of a tree that carries symlinks) can still plant one — the
# write through it, not the plant, is the denied act. `rm` alone skips the
# leaf check: deleting a link removes the link, never its target.
#
# Fails CLOSED, on the same reasoning as `layer-guard.sh`: anything it cannot
# rule on with confidence is denied, because a guard whose failure mode is
# "allow" reports success identically to a guard that works.

set -uo pipefail

deny() {
  echo "Blocked: $1" >&2
  exit 2
}

# Collapse `.` and `..` lexically, then resolve symlinks on the deepest existing
# ancestor. Lexical first, because realpath cannot normalise a path whose leaf
# does not exist yet — which is every file a worker is about to create.
normalise() {
  local path=$1 part joined head tail resolved
  local -a parts=() out=()
  # read -a splits without pathname expansion, so a glob character in a
  # component stays literal instead of expanding against the guard's cwd.
  IFS=/ read -r -a parts <<<"$path"
  for part in ${parts[@]+"${parts[@]}"}; do
    case "$part" in
      '' | .) ;;
      ..) [ ${#out[@]} -gt 0 ] && unset "out[$((${#out[@]} - 1))]" && out=(${out[@]+"${out[@]}"}) ;;
      *) out+=("$part") ;;
    esac
  done
  local IFS=/
  joined="/${out[*]-}"
  IFS=$' \t\n'

  head=$joined
  tail=""
  while [ "$head" != "/" ] && [ ! -e "$head" ]; do
    tail="/$(basename -- "$head")$tail"
    head=$(dirname -- "$head")
  done
  if [ -d "$head" ]; then
    resolved=$(cd -P -- "$head" 2>/dev/null && pwd -P) || resolved=$head
    printf '%s%s' "${resolved%/}" "$tail"
  else
    printf '%s' "$joined"
  fi
}

command -v jq >/dev/null 2>&1 \
  || deny "the guard cannot run — jq is not on PATH, so no write can be ruled on"

uid=$(id -u 2>/dev/null) \
  || deny "the guard cannot read the user id, so the scratchpad root cannot be located"

# The harness keeps every session scratchpad beneath a per-user temp root,
# `<tmpdir>/claude-<uid>/`. No hook environment variable names the exact
# session directory — this derivation mirrors the harness's own, the way
# `layer-guard.sh` derives its root from the environment — so the guard admits
# the per-user root: everything beneath it is harness-managed scratch. Both the
# fixed /tmp base and TMPDIR are probed, whichever the platform used.
# Raw candidates match paths as a shell command spells them; normalised ones
# match what the file tools resolve to. Both are kept: a symlinked temp base
# (macOS's /tmp) makes the two spellings differ.
raw_roots=("/tmp/claude-$uid")
[ -n "${TMPDIR:-}" ] && raw_roots+=("${TMPDIR%/}/claude-$uid")
scratch_roots=()
for root in "${raw_roots[@]}"; do
  candidate=$(normalise "$root")
  case " ${scratch_roots[*]-} " in
    *" $candidate "*) ;;
    *) scratch_roots+=("$candidate") ;;
  esac
done

in_scratch() {
  local path=$1 root
  for root in "${scratch_roots[@]}"; do
    case "$path" in
      "$root" | "$root"/*) return 0 ;;
    esac
  done
  return 1
}

# A tmp/ path is writable only when git confirms the owning repository ignores
# it — untracked scratch, never a tracked file that happens to sit under tmp/.
# Anything git cannot rule on (no repository, no git) stays denied.
ignored_tmp() {
  local path=$1 dir
  case "$path" in
    */tmp | */tmp/*) ;;
    *) return 1 ;;
  esac
  dir=$(dirname -- "$path")
  while [ "$dir" != "/" ] && [ ! -d "$dir" ]; do
    dir=$(dirname -- "$dir")
  done
  git -C "$dir" check-ignore -q -- "$path" 2>/dev/null
}

# Strip one matching pair of surrounding quotes, so a quoted path is judged as
# the path it names. An unbalanced quote survives and fails the later checks.
strip_quotes() {
  local s=$1
  case "$s" in
    \"?*\")
      s=${s#\"}
      s=${s%\"}
      ;;
    \'?*\')
      s=${s#\'}
      s=${s%\'}
      ;;
  esac
  printf '%s' "$s"
}

# A normalised leaf may still alias a file outside the allowance: normalise
# resolves directory symlinks but not a symlinked or hardlinked leaf, so a
# link planted inside scratch would carry a write through to its target. Deny
# a symlink leaf and an existing regular file with a hardlink count above one;
# directories are exempt from the count (their link count is structural).
leaf_unaliased() {
  local p=$1 links
  [ -L "$p" ] && return 1
  if [ -f "$p" ]; then
    # GNU stat first (-c %h); it fails cleanly on BSD, where -f %l is the
    # link count. The reverse order is unsafe: GNU accepts -f %l but prints
    # the filesystem's max filename length.
    links=$(stat -c %h -- "$p" 2>/dev/null) \
      || links=$(stat -f %l -- "$p" 2>/dev/null) \
      || return 1
    [ "$links" = 1 ] || return 1
  fi
  return 0
}

# A path token is inside the write allowance only when it is absolute, carries
# no `..` component, no expansion or quoting the guard cannot resolve, and
# normalises into session scratch or a repository's gitignored tmp/ — with an
# unaliased leaf, so a pre-laid link cannot carry the write outside.
path_in_allowance() {
  local p=$1
  case "$p" in
    *[\$\`\"\']*) return 1 ;;
  esac
  case "/$p/" in
    */../*) return 1 ;;
  esac
  case "$p" in
    /*) ;;
    *) return 1 ;;
  esac
  p=$(normalise "$p")
  in_scratch "$p" || ignored_tmp "$p" || return 1
  leaf_unaliased "$p"
}

scratch_path_ok() {
  path_in_allowance "$(strip_quotes "$1")"
}

# path_in_allowance minus the leaf-alias check. Deleting a link removes the
# link itself, never its target, and decision-160 cleanup must be able to
# remove links the worker legitimately made in scratch.
delete_path_ok() {
  local p
  p=$(strip_quotes "$1")
  case "$p" in
    *[\$\`\"\']*) return 1 ;;
  esac
  case "/$p/" in
    */../*) return 1 ;;
  esac
  case "$p" in
    /*) ;;
    *) return 1 ;;
  esac
  p=$(normalise "$p")
  in_scratch "$p" || ignored_tmp "$p"
}

redirect_target_ok() {
  local p
  p=$(strip_quotes "$1")
  case "$p" in
    /dev/null | /dev/stdout | /dev/stderr | /dev/tty) return 0 ;;
  esac
  path_in_allowance "$p"
}

# A sed script passes only in shapes the guard can prove read-only: a numeric
# or $ address range with p/d/q/=, an s/// or y/// with `/` as the delimiter
# and flags that exclude `e` (execute) and `w` (write), or a /regex/ address
# with p or d. Everything else — `w`, `e`, `r`, branching, other delimiters,
# multi-command scripts — fails, and the worker hands the need back.
sed_script_ok() {
  local s
  s=$(strip_quotes "$1")
  printf '%s' "$s" | grep -Eq \
    '^([0-9]+|\$)?(,([0-9]+|\$))?(p|d|q|=)$|^([0-9]+|\$)?(,([0-9]+|\$))?s/([^/\\]|\\.)*/([^/\\]|\\.)*/[gIip0-9]*$|^/([^/\\]|\\.)*/(p|d)$|^([0-9]+|\$)?(,([0-9]+|\$))?y/([^/\\]|\\.)*/([^/\\]|\\.)*/$'
}

judge_sed() {
  local -a a=("$@")
  local t expect_script=0 script_seen=0
  for t in ${a[@]+"${a[@]}"}; do
    if [ "$expect_script" -eq 1 ]; then
      sed_script_ok "$t" || return 1
      expect_script=0
      script_seen=1
      continue
    fi
    case "$t" in
      -n | -E | -r | -u | --posix | --quiet | --silent | --regexp-extended) ;;
      -e | --expression) expect_script=1 ;;
      -e?*)
        sed_script_ok "${t#-e}" || return 1
        script_seen=1
        ;;
      -*) return 1 ;; # -i, -f, -s and anything unrecognised
      *)
        if [ "$script_seen" -eq 0 ]; then
          sed_script_ok "$t" || return 1
          script_seen=1
        fi
        # subsequent operands are input files: reads
        ;;
    esac
  done
  [ "$expect_script" -eq 0 ]
}

# Judge a `git` fragment's tokens (everything after the `git` word). Read
# subcommands pass with dangerous option shapes denied; `fetch` passes only in
# its narrow ratified forms; any other subcommand is allowed only when the
# invocation is provably scratch-confined: at least one -C/--git-dir/
# --work-tree scope, every scope and every absolute path token inside the
# allowance, no `..`, no expansion, and no subcommand that reaches a remote.
# `-c`, `--config-env` and `--exec-path` are denied everywhere: each injects
# code or binaries into an otherwise read-only invocation.
judge_git() {
  local -a a=("$@") scopes=() rest=()
  local i=0 n=$# t s sub="" names=0 listed=""
  while [ "$i" -lt "$n" ]; do
    t=${a[$i]}
    case "$t" in
      -C | --git-dir | --work-tree)
        i=$((i + 1))
        [ "$i" -lt "$n" ] || return 1
        scopes+=("${a[$i]}")
        ;;
      --git-dir=*) scopes+=("${t#--git-dir=}") ;;
      --work-tree=*) scopes+=("${t#--work-tree=}") ;;
      -P | --no-pager | --no-optional-locks | --literal-pathspecs) ;;
      -*) return 1 ;;
      *)
        sub=$t
        i=$((i + 1))
        break
        ;;
    esac
    i=$((i + 1))
  done
  [ -n "$sub" ] || return 1
  while [ "$i" -lt "$n" ]; do
    rest+=("${a[$i]}")
    i=$((i + 1))
  done

  case "$sub" in
    status | log | show | diff | rev-parse | rev-list | ls-files \
      | check-ignore | blame | grep | cat-file | describe | shortlog \
      | for-each-ref | show-ref)
      # --output writes a file; -O / --open-files-in-pager and --ext-diff run
      # a command named on the line.
      for t in ${rest[@]+"${rest[@]}"}; do
        case "$t" in
          --output* | -O* | --open-files-in-pager* | --ext-diff) return 1 ;;
        esac
      done
      return 0
      ;;
    reflog)
      [ ${#rest[@]} -eq 0 ] && return 0
      case "${rest[0]}" in
        show) return 0 ;;
      esac
      return 1 # delete and expire write
      ;;
    branch)
      for t in ${rest[@]+"${rest[@]}"}; do
        case "$t" in
          --list) listed=y ;;
          -a | -r | -v | -vv | --all | --remotes | --verbose | --sort=* | --format=*) ;;
          -*) return 1 ;;
          *) ;; # a match pattern
        esac
      done
      [ -n "$listed" ]
      ;;
    remote)
      for t in ${rest[@]+"${rest[@]}"}; do
        [ "$t" = "-v" ] || return 1
      done
      return 0
      ;;
    fetch)
      # Ratified narrow forms only: bare, or one plain remote name, optional
      # --prune. A refspec, URL, path or any other flag is denied — a fetch
      # refspec force-writes local branches.
      for t in ${rest[@]+"${rest[@]}"}; do
        case "$t" in
          --prune) ;;
          -*) return 1 ;;
          *)
            names=$((names + 1))
            [ "$names" -le 1 ] || return 1
            printf '%s' "$t" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9_.-]*$' \
              || return 1
            ;;
        esac
      done
      return 0
      ;;
    *)
      case "$sub" in
        push | pull | clone | ls-remote | submodule | archive | bundle \
          | request-pull | send-email | send-pack | http-push | svn | daemon \
          | instaweb)
          return 1
          ;;
        config | maintenance)
          # `config` retargets its write anywhere (--global/--system/--file),
          # and git accepts unambiguous long-flag abbreviations, so no deny
          # list of its flags can hold; `maintenance register|start` writes
          # scheduler state and global config. Both denied whole, whatever
          # -C says. Sandbox commits use the ambient identity.
          return 1
          ;;
      esac
      [ ${#scopes[@]} -gt 0 ] || return 1
      for t in "${scopes[@]}"; do
        scratch_path_ok "$t" || return 1
      done
      # `git -C` chdirs before running, so relative arguments resolve beneath
      # the scoped directory once `..` is excluded; absolute ones — bare or as
      # a flag value — must land inside the allowance themselves. Flags are an
      # exact-match ALLOWLIST: git's parse-options accepts any unambiguous
      # long-flag abbreviation (`--glob` reaches `--global`), so a deny list
      # of flags cannot hold — an unknown or abbreviated flag simply fails
      # this list and denies. A `~` token expands to $HOME in the worker's
      # shell; denied.
      for t in ${rest[@]+"${rest[@]}"}; do
        case "$t" in
          \~*) return 1 ;;
        esac
        case "/$t/" in
          */../*) return 1 ;;
        esac
        case "$t" in
          *[\$\`]*) return 1 ;;
        esac
        s=$(strip_quotes "$t")
        case "$s" in
          /*)
            path_in_allowance "$s" || return 1
            continue
            ;;
          -*=/*)
            path_in_allowance "${s#*=}" || return 1
            continue
            ;;
        esac
        # Judge the stripped token: a quoted flag ("--amend") otherwise
        # matches neither arm and falls through as an operand while the
        # shell unquotes it for git.
        case "$s" in
          -m | -a | -am | -q | --quiet | -b | -f | --force | -d | -u | --) ;;
          -*) return 1 ;;
        esac
      done
      return 0
      ;;
  esac
}

# Judge one fragment's words (redirects already stripped). Deny-by-default:
# the command word must be on the read-only allowlist, with per-command flag
# restrictions where a read tool grows a write or execute flag, or be a
# write-shaped command whose every judged path sits inside the allowance.
judge_words() {
  local cmd=$1
  shift
  local -a a=("$@")
  local t last="" ops=0
  case "$cmd" in
    ls | cat | head | tail | wc | file | stat | du | df | pwd | which \
      | basename | dirname | echo | printf | cut | tr | diff | jq | grep \
      | cd | test | \[ | true | false)
      return 0
      ;;
    date)
      for t in ${a[@]+"${a[@]}"}; do
        case "$t" in
          -s* | --set*) return 1 ;;
        esac
      done
      return 0
      ;;
    sort)
      for t in ${a[@]+"${a[@]}"}; do
        case "$t" in
          -o* | --output* | --compress-program*) return 1 ;;
        esac
      done
      return 0
      ;;
    uniq)
      # A second operand is uniq's output file; flags with separate values
      # over-count and over-deny, which is the accepted direction.
      for t in ${a[@]+"${a[@]}"}; do
        case "$t" in
          -*) ;;
          *) ops=$((ops + 1)) ;;
        esac
      done
      [ "$ops" -le 1 ]
      ;;
    rg)
      for t in ${a[@]+"${a[@]}"}; do
        case "$t" in
          --pre* | --hostname-bin*) return 1 ;;
        esac
      done
      return 0
      ;;
    find)
      for t in ${a[@]+"${a[@]}"}; do
        case "$t" in
          -delete | -exec | -execdir | -ok | -okdir | -fls | -fprint \
            | -fprint0 | -fprintf)
            return 1
            ;;
        esac
      done
      return 0
      ;;
    sed)
      judge_sed ${a[@]+"${a[@]}"}
      ;;
    awk | gawk | mawk | nawk)
      # The program text needs no judging: its write and execute vectors
      # (`>`, `|`, `system(`) carry metacharacters that sever the fragment
      # or fail the redirect check. Flags that load or execute files do not,
      # so they are denied here.
      for t in ${a[@]+"${a[@]}"}; do
        case "$t" in
          -i* | --in-place* | -f* | --file* | -l* | --load* | -E* | --exec*)
            return 1
            ;;
        esac
      done
      return 0
      ;;
    command)
      case "${a[0]-}" in
        -v | -V) return 0 ;;
      esac
      return 1
      ;;
    git)
      judge_git ${a[@]+"${a[@]}"}
      ;;
    rm)
      # rm skips the leaf-alias check (deleting a link never writes through
      # it) but keeps containment: every operand must sit in the allowance.
      for t in ${a[@]+"${a[@]}"}; do
        case "$t" in
          -*) ;;
          *) delete_path_ok "$t" || return 1 ;;
        esac
      done
      return 0
      ;;
    mkdir | touch | ln | truncate)
      # -t on ln names a target directory the operand scan cannot see.
      for t in ${a[@]+"${a[@]}"}; do
        case "$t" in
          -t* | --target-directory*) return 1 ;;
          -*) ;;
          *) scratch_path_ok "$t" || return 1 ;;
        esac
      done
      return 0
      ;;
    cp)
      # Sources are reads and may sit anywhere; the destination — the last
      # operand — must be inside the allowance. Link-creating flags (-s/-l,
      # short bundles included) are denied, and long options are denied
      # wholesale: GNU cp abbreviates them, so `--symbolic` reaches
      # --symbolic-link and only exact short flags can be judged. -t names
      # the destination elsewhere; denied rather than tracked.
      for t in ${a[@]+"${a[@]}"}; do
        case "$t" in
          --) continue ;;
          --* | -t*) return 1 ;;
          -*[sl]*) return 1 ;;
          -*) ;;
          *) last=$t ;;
        esac
      done
      [ -n "$last" ] || return 1
      scratch_path_ok "$last"
      ;;
    mv)
      # mv unlinks its source: an outside source is an outside write, so
      # every operand — source and destination alike — must sit inside the
      # allowance. -t names a destination the operand scan cannot see;
      # denied. Long options denied as on cp; bare -- passes.
      for t in ${a[@]+"${a[@]}"}; do
        case "$t" in
          --) continue ;;
          --* | -t*) return 1 ;;
          -*) ;;
          *)
            scratch_path_ok "$t" || return 1
            ops=$((ops + 1))
            ;;
        esac
      done
      [ "$ops" -ge 2 ]
      ;;
    tee)
      for t in ${a[@]+"${a[@]}"}; do
        case "$t" in
          -*) ;;
          *) scratch_path_ok "$t" || return 1 ;;
        esac
      done
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Judge one metacharacter-free fragment: validate and strip redirects, then
# hand the remaining words to the allowlist. An empty fragment, or one that is
# only redirects into the allowance, passes.
judge_fragment() {
  local frag=$1 t target i n
  local -a toks=() words=()
  frag=${frag#"${frag%%[![:space:]]*}"}
  frag=${frag%"${frag##*[![:space:]]}"}
  [ -n "$frag" ] || return 0

  IFS=$' \t' read -r -a toks <<<"$frag"
  n=${#toks[@]}
  i=0
  while [ "$i" -lt "$n" ]; do
    t=${toks[$i]}
    case "$t" in
      \<\< | \<\<- | \<\<\< | \< | [0-9]\<)
        i=$((i + 1)) # heredoc delimiter or input file as next token: a read
        ;;
      \<\<* | [0-9]\<\<* | \<* | [0-9]\<*)
        ;; # attached input operand: a read
      \> | \>\> | [0-9]\> | [0-9]\>\>)
        i=$((i + 1))
        [ "$i" -lt "$n" ] || return 1 # dangling redirect
        redirect_target_ok "${toks[$i]}" || return 1
        ;;
      \>* | [0-9]\>*)
        target=$t
        target=${target#[0-9]}
        target=${target#\>}
        target=${target#\>}
        redirect_target_ok "$target" || return 1
        ;;
      *\>* | *\<*)
        return 1 # a redirect shape the guard does not recognise
        ;;
      *)
        words+=("$t")
        ;;
    esac
    i=$((i + 1))
  done

  [ ${#words[@]} -gt 0 ] || return 0
  judge_words "${words[@]}"
}

input=$(cat) || deny "the guard could not read the tool call"
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty') \
  || deny "the tool call is not parseable JSON"

# Paths the file tools carry. Bash is handled separately below, because a shell
# command has no path field to read.
target=$(printf '%s' "$input" \
  | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')

case "$tool" in
  Write | Edit | NotebookEdit)
    [ -n "$target" ] \
      || deny "$tool carried no path, so the guard cannot rule on it"
    case "$target" in
      /*) ;;
      *) deny "$tool carried the relative path $target, which the guard cannot resolve" ;;
    esac
    case "/$target/" in
      */../*) deny "$tool carried a path with a .. component, which the guard denies outright: a symlink before the .. escapes any lexical check" ;;
    esac
    # Normalisation reads the path line-wise, so everything after a newline
    # would escape the symlink and hardlink leaf checks. No legitimate scratch
    # write needs a newline in its path; deny outright.
    case "$target" in
      *$'\n'*) deny "$tool carried a path containing a newline, which the guard denies outright: it cannot be judged whole" ;;
    esac

    resolved=$(normalise "$target")
    if in_scratch "$resolved" || ignored_tmp "$resolved"; then
      # The leaf may alias a file elsewhere: a symlink writes through to its
      # target, and a hardlinked inode is the outside file. Deny both.
      [ -L "$resolved" ] \
        && deny "$resolved is a symlink, which would carry the write outside the judged path"
      if [ -f "$resolved" ]; then
        # GNU stat first (-c %h); it fails cleanly on BSD, where -f %l is the
        # link count. The reverse order is unsafe: GNU accepts -f %l but
        # prints the filesystem's max filename length.
        links=$(stat -c %h -- "$resolved" 2>/dev/null) \
          || links=$(stat -f %l -- "$resolved" 2>/dev/null) \
          || deny "the guard cannot read the link count of $resolved, so it cannot rule out a hardlink alias"
        case "$links" in
          1) ;;
          *) deny "$resolved has a link count of $links, so the guard cannot rule out a hardlink alias of a file outside the judged path" ;;
        esac
      fi
      exit 0
    fi
    deny "a write-nothing worker writes only session scratch and a repository's gitignored tmp/; $resolved is neither"
    ;;

  Bash)
    command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
    [ -n "$command" ] || exit 0

    # Deny-by-default. fd duplications are blanked first so 2>&1 and >&2
    # survive the split on `&`; then every chaining or substituting separator
    # becomes a fragment boundary and each fragment must pass on its own.
    # shellcheck disable=SC2020 # tr's set2 repeats \n on purpose: char-per-char
    fragments=$(printf '%s\n' "$command" \
      | sed -E -e 's/[0-9]*>&[0-9]+-?//g' -e 's/[0-9]*<&[0-9]+-?//g' \
        -e 's/[<>]&-//g' \
      | tr ';&|()`' '\n\n\n\n\n\n')
    while IFS= read -r fragment; do
      judge_fragment "$fragment" \
        || deny "a write-nothing worker's Bash is allowlisted, deny-by-default; the fragment '$fragment' matches no recognised read-only shape and is not confined to session scratch or a gitignored tmp/"
    done <<<"$fragments"
    exit 0
    ;;

  # Known read-only or session-local tools pass through. Anything else —
  # including a tool this guard has never heard of — is denied, because an
  # unrecognised tool's write surface cannot be judged. Task is deliberately
  # absent: a write-nothing worker has no business spawning subagents, and
  # hook propagation to a subagent is unverified.
  Read | Glob | Grep | NotebookRead | BashOutput | KillShell | TodoWrite \
    | Skill | ToolSearch | SlashCommand | WebFetch | WebSearch \
    | AskUserQuestion | ExitPlanMode | ListMcpResources | ReadMcpResource)
    exit 0
    ;;

  '')
    deny "the tool call names no tool, so the guard cannot rule on it"
    ;;

  *)
    deny "the guard does not recognise the tool $tool, and an unrecognised tool is denied rather than guessed at"
    ;;
esac
