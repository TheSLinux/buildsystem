#!/bin/bash

# Purpose: Various tools (See function docs.)
# Author : Anh K. Huynh
# License: GPL v2
# Date   : 2013 March 30th

_msg() {
  echo ":: $*"
}

_err() {
  echo >&2 ":: Error: $*"
}

_die() {
  _err "$*"
  exit 1
}

# Date   : 2013 March 30th
# Purpose: Import a package from ABS to current repository
# Usage  : $0 <package_name>
#
#   a/   : Where to store ABS packages in the structure
#             <package-1>/trunk/
#             <package-2>/trunk
#          This is because ABS is in SVN structure, and the most
#          development stuff is in the directory `/trunk/`
#
#   ./   : where to import new package
#

_D_ABS="${ABS:-$PWD/a/}"    # where to store ABS system

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
  && git co -b "$_pkg" "TheBigBang" \
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
        || {
          _err "svn info failed to run in $_ds"
          popd; return 1
        }

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

# Import all packages provided in the arguments
import() {
  while (( $# )); do
    _import_package $1
    shift
  done
}

# Date   : 2013 April 6th
# Purpose: Migration the old repository to the new one
# Usage  : $0 /path/to/the/original/source/tree [package]
# Story  : During the migration I suddenly delete the directory `.git`
#          of the old repository that have some branches that are not
#          pushed to remoted. Fortunately their patch files are stil
#          there ;)
#
# This script is used to convert the old repository to the new one
#
# The old one: Every package has its own branch; the branches are merged
# and reabased on the master. This is very messy, confused. In this repo,
# most commits for packages (the branch `_utils` is not a package) are in
# two forms:
#
#   a. the importing commit (import package from abs source)
#   b. the patch commit (slight modification of the first commit)
#
# Except for the two branches `m17n-db` and `m17n-db-vi`, most commits
# should fit in a single package (path).
#
# The new one: The master has the very basic information. New package has
# its own branch **that starts** from the very first commit of the master.
# To convert from the old commits, we
#
#   1. first we rebase all packages/branches on the master
#   2. check every commit if it is of type a. or b. (above)
#   3. of type a.: create new import commit
#   4. of type b.: generate patch file and apply it to the branch.
#
# We need to treat the following branches specially
#
#   1. linux-g1: the first branch, has the first commit
#   2. m17n-db:
#   3. m17n-db-vi: start from some commit in `m17n-db`
#   4. p_*: used to generate patch files
#
# Notes:
#   1. We need directory `/tmp/` in the current working directory
#   2. During the migration the package `_utils` (not actually a package,
#      though) is in the blacklist. The migration process is quite good,
#      except the package `linux-api-header` can't be converted and we
#      would transfer it to new repo. manually. When the package `_utils`
#      is removed from the blacklist, a new branch `_utils` needs to be
#      created **manually** because this branch doesn't have any `import`
#      phase as other real package.
#   3. The branch `master` on the old repository should contain all changes
#      from the other packages (with helps of `git rebase`). This is the
#      essential key for the migration process.
#
convert() {
  local _cwd="$PWD"   # current workding dir
  local _prev=        # previous commit
  local _is_first=1   # is that the first commit
  local _pkg=         # the new package
  local _count=0      # number of basedir in a commit
  local _subject=     # subject of a commit
  local _blacklist=" linux-g1 m17n-db m17n-db-vi "
                      # some special packages as mentioned above
  local _bigbang="TheBigBang"
                      # This is where we create new branch for new package
                      # Using a branch name is better here.
  local _f_tmp=       # a temporary patch file. This won't hurt!

  pushd "$_cwd"

  cd "$1" \
  || { popd; _err "Failed to switch to '$1'"; return 1; }

  _pkg="$2"

  git log \
  | grep "^commit" \
  | awk '{print $NF}' \
  | tac \
  | while read _commit; do
      # save the first commit and move to the next step
      if [[ "$_is_first" == "1" ]]; then
        _is_first="$_commit"
        _prev="$_commit"
        continue
      fi

      _msg "New migration: $_prev -> $_commit"
      _f_tmp="$_cwd/tmp/patch.$_prev.$_commit"

      _count=0
      git diff --name-only "$_prev" "$_commit" \
      | awk -F / '{print $1}' \
      | sort -u \
      | while read _path; do
          if [[ "$_count" == "1" ]]; then
            _err "$_path: multiple path found in a single commit. Skip"
            continue
          fi

          if [[ -n "$_pkg" && "$_pkg" != "$_path" ]]; then
            _msg "$_path: Skip as we need only the package $_pkg"
            continue
          fi

          echo "$_blacklist" | grep -q " $_path "
          if [[ $? -eq 0 ]]; then
            _msg "$_path: Package is in the blacklist. Skip"
            continue
          fi

          if [[ "${_path:0:2}" == "p_" ]]; then
            _msg "$_path: Package is a patch (not new package). Skip"
            continue
          fi

          # Generate the patch file
          git format-patch --stdout "$_prev".."$_commit" \
            > "$_f_tmp"

          _subject="$(git log -1 --pretty='format:%s' $_commit)"

          pushd "$_cwd"

          # There is a typo error when importing `filesystem` that
          # the subject of commit has `Immport` not `Import` as usual.
          echo "$_subject" | grep -qE "Import|Immport"
          if [[ $? -eq 0 ]]; then
            # This is an Import commit, we need to create new branch

            git branch | grep -Eq "^ $_path$"
            if [[ $? -eq 0 ]]; then
              _err "$_path: The branch does exist. Something wrong happened"
              popd
              continue
            fi

            git checkout -b "$_path" "$_bigbang" \
            || {
              popd
              _err "$_path: Failed to create new branch"
              continue
            }
          else
            git checkout "$_path" \
            || {
              popd
              _err "$_path: Failed to switch to the branch"
              continue
            }
          fi

          if git apply --check "$_f_tmp" >/dev/null; then
            git am < "$_f_tmp" \
            || _err "$_path: Weird. Good check with a failed patch?"
          else
            _err "$_path: The patch won't be applied."
          fi

          popd

          (( _count ++ ))
        done

      _prev="$_commit"
    done

  popd
  git co master
}

(( $# )) || _die "Missing arguments"

$*
