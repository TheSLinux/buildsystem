#!/bin/bash

# Purpose: Various tools (See function docs.)
# Author : Anh K. Huynh
# License: GPL v2
# Date   : 2013 March 30th

_msg() {
  echo ":: $@"
}

_err() {
  echo >&2 ":: Error: $@"
}

_warn() {
  echo >&2 ":: Warning: $@"
}

_die() {
  _err "$@"
  exit 1
}

# Don't use `wc -l`, bc that `git` will not return `newline` at EOF.
# See also https://twitter.com/kyanh/status/325193878753923072
# and https://twitter.com/kyanh/status/325196732952637441
#
_linecount() {
  awk 'BEGIN{l=0}{l++}END{print l}'
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

_D_ABS="${ABS:-$PWD/a/ $PWD/b/}"    # where to store ABS system

_import_package() {
  local _pkg="$1"                     # package name
  local _ds=""                        # path to package/trunk
  local _dd="$PWD/$_pkg/"             # path to desntination
  local _rev=                         # package revision (SVN)
  local _f_readme="$_dd/README.md"    # the reade file

  _msg ">> Trying to import package $_pkg <<"

  [[ ! -d "$_dd/" ]] \
  || { _err "Directory does exist $_dd"; return 1; }

  # Find the first ABS source that contains `$_pkg`
  for _ds in $_D_ABS; do
    [[ ! -d "$_ds/$_pkg/trunk/" ]] || break
  done

  # If we don't find any $_pkg in current list of sources
  # we will try to invoke `svn update` in every source. Please note that
  # the command `svn update non-existent-package` will return 0 even if
  # the package doesn't exist in the ArchLinux's ABS system. There is
  # two ways to check if there is a package: `svn ls` and `svn update`.
  if [[ ! -d "$_ds/$_pkg/trunk/" ]]; then
    for _ds in $_D_ABS; do
      pushd "$_ds/"
      _msg "Invoking svn update in $_ds/"
      svn update "$_pkg"
      # After invoking `svn update` we need to check if the directory
      # for our package `$_pkg` does exist.
      [[ ! -d "$_ds/$_pkg/trunk" ]] || { popd; break; }
      popd
    done
  fi

  # We scan all ABS sources again to see if there is `$_pkg`
  for _ds in $_D_ABS; do
    [[ ! -d "$_ds/$_pkg/trunk/" ]] || break
  done

  _ds="$_ds/$_pkg/trunk/"

  # If we don't find it at all, return with error
  [[ -d "$_ds/" ]] \
  || { _err "Directory not found  $_ds"; return 1; }

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

        svn update >/dev/null 2>&1 \
        || {
          _err "svn update failed to run in $_ds"
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

  _die "The migration was complete. This function now stops."

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

# Get the current git branch in the working directory.
# Input
#   => Working directory is a git directory
#
_get_git_branch() {
  local _br=
  _br="$(git rev-parse --abbrev-ref HEAD)"
  if [[ -z "$_br" ]]; then
    _error "Failed to run 'git branch' in $PWD"
    return 1
  else
    echo "$_br"
  fi
}

# Get the package name if the branch name and working directory is the same.
# The common rules (TheBigBang) says that the package branch would be
# the package name, and it's the same as the working directory. If
# there is any difference (for example when we are working on patch branch)
# the branch name would be got from the environment `PACKAGE_BASE`.
# We don't have any way to check if `PACKAGE_BASE` matches the current
# working directory.
#
# FIXME: + more description and illustration
#
# Input
#   => Working directory is a package directory
#   => PACKAGE_BASE (env. var.) is set
#
_get_package_name() {
  local _wd="$(basename $PWD)"
  local _br=

  if _br="$(_get_git_branch)"; then
    if [[ "$_br" == "$_wd" ]]; then
      echo "$_br"
      return 0
    elif [[ "$_wd" == "${PACKAGE_BASE:-}" ]]; then
      _warn "Getting branch name from the environment PACKAGE_BASE"
      echo "$PACKAGE_BASE"
      return 0
    else
      _err "Working directory \"$_wd\" and working branch \"$_br\" are not matched"
    fi
  fi
  return 1
}

# Get the point on `TheBigBang` where a branch starts. See also
# http://stackoverflow.com/questions/1527234/finding-a-branch-point-with-git
#
# The branch name is got from the first argument. If no argument is
# provided, the `HEAD` is used instead. Please note that our package
# branch always starts from `TheBigBang`.
#
# The output would be some commint on the branch `TheBigBang`, and it
# should not be always the starting point the `TheBigBang`.
#
#  ---*---o--------*----*----*----- thebigbang
#         \--*---*----*----*----*-- package branch
#                \--*----*----*---- patch branch
#
# The brach point for both branches `package` and `patch` is `o`.
#
# Input
#   $1 => Any branch name
#
_get_git_branch_point() {
  local _point=

  _point="$( \
    diff -u \
      <(git rev-list --first-parent "${1:-HEAD}" --) \
      <(git rev-list --first-parent "TheBigBang" --) \
    | sed -ne 's/^ //p' \
    | head -1)"

  if [[ -z "$_point" ]]; then
    _err "Failed to get the branch point for ${1:-HEAD}'"
    return 1
  else
    echo "$_point"
  fi
}

# Return the number of commits between two points. This will actually
# return number of commits that are on the `dest` and not on the `source`.
#
#  ---*---o--------*----*----*----- thebigbang
#         \--*---*----*----*----*-- package branch
#                \--*----*----*---- patch branch
#
#   thebigbang .. package branch  => 5
#   thebigbang .. patch branch    => 3
#   package branch .. thebigbang  => 3
#
# The branch point `o` is excluded from the output.
#
# Input
#   $1 => The starting point (a branch name)
#   $2 => The end point (a branch name
#   $@ => Optional arguments for `git log`
#
_get_git_commits_between_two_points() {
  local _from="$1"; shift
  local _to="${1:-HEAD}"; shift

  git log --pretty="format:%H" "$_from".."$_to" "$@"
  # This is tricky to add newline to EOF. This help the output is countable
  # by `wc`, and readable by `while` loop. Without a `newline` at the end,
  # the last line from the output will be ignored by `while` loop.
  # FIXME: This possibly change in the future, by `git`. Should find
  # FIXME: a more robust way and add a test case to ensure things work.
  echo
}

# See also (_get_git_commits_between_two_points)
# Input
#   $1 => The starting point (a branch name)
#   $2 => The end point (a branch name)
#   $@ => Optional arguments for `_get_git_commits_between_two_points`
#
_get_number_of_git_commits_between_two_points() {
  local _from="$1"; shift
  local _to="${1:-HEAD}"; shift
  local _num=

  _num="$(_get_git_commits_between_two_points $_from $_to "$@" | _linecount)"
  # FIXME: `_num` will never be empty. We need another way
  # FIXME: to check error. This is a bad deal in Bash.
  if [[ -z "$_num" ]]; then
    echo 0
    return 1
  else
    echo "$_num"
  fi
}

# Get the number of changes from a branch/HEAD to its branch point
# (the point where it is started.) If there is something wrong with
# `git` we will return error code 1 and print to STDOUT the number 0.
# The `branc point` will be excluded.
#
# Please note that 1 is the mininum result that is acceptable by `makepkg`
#
#  ---o----*-----*----*-----*--- master
#      \-*----*----------*------ thebigbang
#
# On `master`:      4 commits since the branch point
# On `thebigbang:`  3 commits since the branch point
#
# Input
#   $1 => the branch name
#   $@ => Optional arguments for `_get_number_of_git_commits_between_two_points`
#
_get_number_of_git_commits_from_branch_point() {
  local _point=
  local _num=
  local _br="${1:-HEAD}"; shift

  if _point="$(_get_git_branch_point ${1:-HEAD})"; then
    _get_number_of_git_commits_between_two_points "$_point" "$_br" "$@"
  else
    echo 0
    return 1
  fi
}

# Return -all tags- the first tag on the *package branch*, that is also
# the latest tag until the current time / commit (despite the name due
# to a history version, the function only return one tag.)
#
# Note, on the branch `PACKAGE_BASE` we may have different kinds of tags:
# temporary tag, release tag,...; we will list all tags and get one. To
# do that, we will (1) list all commits since `TheBigBang`, and (2) get
# every tags associcated with those commit, and (3) find the good tag.
#
# The `good tag` matches the pattern `PACKAGE_BASE-x.y.z(-release)?`
#
# FIXME: This is very *slow*. Please find a better way
#
#  ---o----*-----*----*-----*--- thebigbang
#      \-*----*----o-----o---o-- package branch
#             |    |     |   |
#             \-*--|--*--|---|-- working branch
#                  |     |   |
#                  |      \--+-- these tags should be ignored
#                  |
#                  \--- acceptable tag
#
# Notes: What does `git tag --contains <commit>` mean? See below
#
#  --*---^--...
#     \          /---------------------- how to get this point ?
#      *--*--*---o---o---o--o---?--?---- package branch
#      U     T   |          S      R
#                \--#--#---------------- the development branch
#
# The tag `T` contains any `*`. The tag `S`, `R` contain any `*` and `o`.
# So `git tag --contains` will return a list of commits. And that list
# will not help to find the correct tag.
#
# There may be two different ways to get *the tag we want*
#
#   1. Return tag `T` for any `o` (but don't return `S`)
#   2. Return tag `S` for any `o` (but don't return `R`)
#
# We want to find the next version tag, we want to get the `latest`
# tag, do some increment (something like `T + 1`) to the next tag.
# So we will use `1.`: return the latest tag just before working time.
#
# Input
#   $1 => The branch name on that you want get the latest tag
#   $2 => The reference point to get the time (usually the working branch)
#

_get_git_tag_on_package_branch() {
  _get_git_tags_on_package_branch "$@"
}

_get_git_tags_on_package_branch() {
  local _br="${1:-HEAD}"
  local _ref="${2:-HEAD}"
  local _gs=
  local _tag=
  local _commmit=
  local _ref_time=

  if ! _ref_time="$(git log -1 --pretty='format:%ct' $_ref --)"; then
    _err "Failed to get info. from (possibly invalid) reference point '$_ref'"
    return 1
  fi

  if [[ "$_br" == "HEAD" ]]; then
    if ! _br="$(_get_git_branch)"; then
      _err "Failed to get current branch"
      return 1
    fi
  fi

  while read _commit; do
    if _tag="$(git describe --tags --exact-match $_commit 2>/dev/null)"; then
      ruby \
        -e "_tag=\"$_tag\"" \
        -e "_br=\"$_br\"" \
        -e 'exit _tag.match(/^#{_br}-[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?$/) ? 0 : 1'

      if [[ $? -eq 0 ]]; then
        echo "$_tag"
        return 0
      fi
    fi
  done < \
    <(_get_git_commits_between_two_points TheBigBang "$_br" --until="$_ref_time")

  return 1
}

# Return the version number from a tag
# Input
#   $1 => The current tag
#
_get_version_from_tag() {
  local _tag="$1"
  ruby \
    -e "_tag=\"$_tag\"" \
    -e 'if gs=_tag.match(/^.+-([0-9]+\.[0-9]+\.[0-9]+)(-[0-9]+)?$/)
          puts gs[1]
        else
          exit 1
        end'
}

# Return the release number of a tag
# Input
#   $1 => The current tag
_get_release_from_tag() {
  local _tag="$1"
  ruby \
    -e "_tag=\"$_tag\"" \
    -e 'if gs=_tag.match(/^.+-[0-9]+\.[0-9]+\.[0-9]+(-([0-9]+))?$/)
          puts gs[1] ? gs[2] : 1
        else
          exit 1
        end'
}

# Return the next tag from current tag + working branch
# Input
#   $1 => The current tag
#   $2 => The working branch (as reference)
_get_next_tag_from_tag() {
  local _tag="$1"
  local _ref="${2:-HEAD}"
  local _rel=

  _rel="$(_get_number_of_git_commits_between_two_points $_tag $_ref)"
  ruby \
    -e "_tag=\"$_tag\"" \
    -e "_rel=$_rel" \
    -e 'if gs=_tag.match(/^(.+-[0-9]+\.[0-9]+\.[0-9]+)(-([0-9]+))?$/)
          _rel += gs[2] ? gs[3].to_i : 1
          puts "#{gs[1]}-#{_rel}"
        else
          exit 1
        end'
}

# Return the next tag (the current tag is implicitly provided.)
# Input
#   => nothing
_get_next_tag() {
  local _tag
  if _tag="$(_get_current_tag)"; then
    _get_next_tag_from_tag "$_tag"
  else
    return 1
  fi
}

# Return the latest tag on the current working branch
# Input
#   => nothing
_get_current_tag() {
  local _br=
  if _br="$(_get_git_branch)"; then
    _get_git_tag_on_package_branch $_br
  else
    return 1
  fi
}

# Get the latest version of the a package branch. We need to find a tag
# that: (1) is on the branch `PACKAGE_BASE`, (2) it is the latest tag
# before the current HEAD/point (3) its name matches `PACKAGE_BASE`.
#
# As this function can run on any branch we need the environment var.
# `PACKAGE_BASE`. This also means it can work on at most one package
# at the same time.
#
# If we can not find the package version, we will return the first version
# of the package. This is not a recommendation, though.
#
# This function is useful if we are on patching branch for a package.
#
#  ---*---o-----*---*----*----*-------- thebigbang
#         |
#         \--x----*-*----x----*-----*-- package branch `foobar`
#            |    | |    |          |
#            |    | \--*-|--*----*--|-- patch branch `p_foobar-stuff`
#            |    |      |       |  |
#            |    |   foobar-y   |  |
#            |     \             |  \-- foobar-y-<release = 2+1>
#            |      |            |
#        foobar-x   |            \----- foobar-y-<release = 3+1> (!!)
#            |      |
#            |      \--- foobar-x-<release = 1+1>
#            |
#       release = 0+1
#
# Input
#   $1 => the branch name. Default: PACKAGE_BASE
#
_get_package_version() {
  local _ver=
  local _rel=
  local _point=
  local _pkg="${1:-$PACKAGE_BASE}"

  if [[ -z "$_pkg" ]]; then
    _err "Environment not set PACKAGE_BASE or package name isn't provided"
    return 1
  fi

  if _point="$(git describe --abbrev=0 --tags ${_pkg})"; then
    echo 0
  else
    echo ""
    return 1
  fi
}

# TheSLinux's version of Arch makepkg. This will check and generate
# some environment variables before invoking the real program `makepkg`.
# Note: the dash (-) hides this function from Geany symbols listing
s-makepkg() {
  local _tag=
  local _ver=
  local _rel=
  local _pkg=

  _pkg="$(_get_package_name)" \
  || { _err "Failed to get package name"; return 1; }

  if _tag="$(_get_git_tag_on_package_branch ${_pkg})"; then
    if _ver="$(_get_version_from_tag $_tag)"; then
      if _rel="$(_get_release_from_tag $_tag)"; then
        :; \
          PACKAGE_BASE="$_pkg" \
          PACKAGE_RELEASE="$_rel" \
          PACKAGE_VERSION="$_ver" \
          exec makepkg "$@"
      else
        _err "Failed to get release number from tag '$_tag'"
      fi
    else
      _err "Failed to get version number from tag '$_tag'"
    fi
  else
    _err "Failed to get current tag on the branch '$(_get_git_branch)'"
  fi
  return 1
}

# This is used to update this script by invoking `git pull --rebase`.
# It's a quite dangerous way :)
selfupdate() {
  pushd .
  cd "$(dirname $0)" \
  && {
    git pull --rebase
  }
  popd .
}

(( $# )) || _die "Missing arguments"

"$@"
