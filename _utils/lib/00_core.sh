# Purpose: Basic bash routines
# Author : Anh K. Huynh
# License: GPL v2 (http://www.gnu.org/licenses/gpl-2.0.html)
# Date   : 2014 Apr 15th (moved from the original `run.sh`)
# Home   : https://github.com/TheSLinux/buildsystem/tree/_utils

_msg() {
  echo ":: $@"
}

_err() {
  echo >&2 ":: Error: $@"
  return 1
}

_warn() {
  echo >&2 ":: Warning: $@"
}

_die() {
  _err "$@"
  exit 1
}

# Check if a pipe is good: That one contains only zero (0) return codes.
# NOTE: You must use this *immediately* after any pipe. Any command
# NOTE: in Bash can be considered as a simple pipe.
_is_good_pipe() {
  echo "${PIPESTATUS[@]}" | grep -qE "^[0 ]+$"
}

# Don't use `wc -l`, bc that `git` will not return `newline` at EOF.
# See also https://twitter.com/kyanh/status/325193878753923072
# and https://twitter.com/kyanh/status/325196732952637441
#
_linecount() {
  awk 'BEGIN{l=0}{l++}END{print l}'
}
