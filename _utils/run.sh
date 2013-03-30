#!/bin/bash

# Purpose: Import some packages from ABS system
# Author : Anh K. Huynh
# License: GPL v2
# Date   : 2013 March 30th
#
# Usage  :
#
#   a/   : where to store ABS packages in the structure
#             <package>/trunk/
#             <package>/trunk
#
#   ./   : where to import new package
#

_D_ABS="$PWD/a/"    # where to store ABS system

_msg() {
  echo ":: $*"
}

_err() {
  echo >&2 ":: $*"
}

_die() {
  _err "$*"
  exit 1
}

_import_package() {
  local _pkg="$1"                     # package name
  local _ds="$_D_ABS/$_pkg/trunk"     # path to package/trunk
  local _dd="$PWD/$_pkg/"             # path to desntination
  local _rev=                         # package revision (SVN)
  local _f_readme="$_dd/README.md"    # the reade file

  _msg ">> Trying to import package $_pkg <<"

  [[ -d "$_ds/" ]] \
  || { _err "Directory not found  $_ds"; return 1; }

  [[ ! -d "$_dd/" ]] \
  || { _err "Directory does exist $_dd"; return 1; }

  # We nee to be on the master before creating new branch
  git co master \
  && git co -b "$_pkg" \
  && {
    cp -r "$_ds/" "$_dd/"

    # Generate the README.md
    [[ -f "$_f_readme" ]] \
    || {
      pushd "$PWD"

      cd "$_ds/" \
      && {
        # Test if svn return any error
        svn info >/dev/null 2>&1 \
          || { _err "svn info failed to run in $_ds"; return 1; }

        # Get the revision information
        _rev="$(svn info | grep ^Revision: | head -1 | awk '{print $NF}')"

        # Readmin contents
        {
          echo "Import from ArchLinux's ABS"
          echo ""
          svn info \
            | grep -E "^(URL|Revision):"
        } \
          > "$_f_readme"
      }

      popd
    }

    # Genereate git commit
    git add "$_dd" \
      && git commit "$_pkg/" -m"$_pkg: Import from ABS @ $_rev" \
      && git push origin "$_pkg" \
      && git branch --set-upstream-to="origin/$_pkg" \
      && git co master \
      || { _err "Something wrong with git repository"; return 1; }
    } \
  || {
    _err "Failed to switch to 'master' or to create new branch $_pkg"
    return 1
  }
}

import() {
  while (( $# )); do
    _import_package $1
    shift
  done
}

(( $# )) || _die "Missing arguments"

$*
