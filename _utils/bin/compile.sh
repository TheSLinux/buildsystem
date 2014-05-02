#!/bin/bash

# Purpose: Generate a `case` statement to detect whether a function is
#          exported from one of our libraries (from ./lib/*.sh)
# Author : Anh K. Huynh
# Date   : 2014 May 2nd
# License: MIT

set -e
set -u

unset GREP_OPTIONS \
|| { echo >&2 "Unable to unset 'GREP_OPTIONS'"; exit 1; }

cat run2.sh
for f in ./lib/*.sh; do
  if [[ "${f##*/}" == "zz_main.sh" ]]; then
    echo ""
    echo "# Exported functions. Code generated by ./bin/compile.sh"
    echo ""
    echo "unset _func || _die \"Unable to update '_func' variable\""
    echo 'case "${0##*/}" in'
    grep '^:export ' lib/* -h \
    | awk '{
        if (match($0, /:export ([^ ]+)[ ]+(.+)/, m)) {
          printf("  \"%s\") _func=\"%s\" ;;\n", m[1], m[2]);
        }
      }'
    echo '  *) _func="" ;;'
    echo 'esac'
  fi
  echo >&2 "- processing $f ..."
  echo ""
  echo "# Source file = $f"
  echo ""
  cat $f
done
