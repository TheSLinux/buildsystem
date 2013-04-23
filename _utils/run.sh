#!/bin/bash

# Purpose: Various tools (See function docs.)
# Author : Anh K. Huynh
# License: GPL v2 (http://www.gnu.org/licenses/gpl-2.0.html)
# Date   : 2013 March 30th
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
  local _pkgver=

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

    if _pkgver="$(git show "$_pkg:$_pkg/PKGBUILD" \
                | _get_version_from_old_PKGBUILD ;\
              [[ ${PIPESTATUS[0]} -eq 0 ]] \
              && [[ ${PIPESTATUS[1]} -eq 0 ]] \
              || exit 1 \
            )" ; then
      git tag -a \
        -m "The original source from the ABS" \
        "${_pkg}-${_pkgver}" "$_pkg"
      git push origin "${_pkg}-${_pkgver}"
    else
      _err "Failed to get version number from PKGBUILD of $_pkg"
    fi
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
# or check if a local branch does exist.
#
# Input
#   $1 => branch => A branch to check if it exist
#   $1 => empty  => Get current branch in working directory
#
_get_git_branch() {
  local _br=
  if [[ -n "$1" ]]; then
    git show-branch "$1" >/dev/null \
    && echo "$1" \
    || return 1
  else
    _br="$(git rev-parse --abbrev-ref HEAD)" \
    && echo "$_br" \
    || _err "Failed to run geat HEAD information in $PWD"
  fi
}

# Get the package name from the working directory / branch.
#
# The common rules (TheBigBang) says that the package branch would be
# the package name, and it's the same as the working directory. The work-
# ing directory will play the main role. It is used to test if the branch
# is the package branch or a feature branch of the package.
#
# If the environment `PACKAGE_BASE` is provided, and it matches the work-
# ing directory, the program will return that variable.
#
# Conventions: A feature branch should start with `p_`, follow by the
# package name, and the feature (if any). Example
#
#   p_foobar
#   p_foobar+feature   foobar+feature
#   p_foobar#feature   foobar#feature
#   p_foobar=feature   foobar=feature
#   p_foobar%feature   foobar%feature
#   p_foobar@feature   foobar@feature
#
# Input
#   => Working directory is a package directory
#   => PACKAGE_BASE (env. var.) is set
#
_get_package_name() {
  local _wd="$(basename $PWD)"
  local _br=
  local _tag=

  # Check if tag is provided
  _tag="${PACKAGE_TAG:-}"
  _tag="${_tag:-$PACKAGE_REF_TAG}"

  [[ -z "$_tag" ]] \
  || _br="$(_get_package_name_from_tag $_tag)" \
  || return 1

  _br="${_br:-$PACKAGE_BASE}"

  # Make sure there is local branch
  _br="$(_get_git_branch "$_br")" || return 1

  # We only need to check for the last case (br = <current branch>)
  ruby \
    -e "_br=\"$_br\"" \
    -e "_wd=\"$_wd\"" \
    -e 'if _br.match(%r{^(p_)?#{_wd}([@+#=%].+)?$})
          exit 0
        else
          STDERR.puts ":: Error: Branch \"#{_br}\" and directory \"#{_wd}\" do not match"
          exit 1
        end
      ' \
  && echo "$_wd" \
  || return 1
}

# Return the number of commits between two points. This will actually
# return number of commits that are on the `dest` and not on the `source`.
#
#  ---*---o--------*----*----*----- thebigbang
#         \--*---*----*----*----*-- package branch
#                \--*----*----*---- feature branch
#
#   thebigbang .. package branch  => 5
#   thebigbang .. feature branch  => 3
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

  # Using of `echo`:
  # This is tricky to add newline to EOF. This help the output is countable
  # by `wc`, and readable by `while` loop. Without a `newline` at the end,
  # the last line from the output will be ignored by `while` loop.
  # FIXME: This possibly change in the future, by `git`. Should find
  # FIXME: a more robust way and add a test case to ensure things work.
  git log --pretty="format:%H" "$_from".."$_to" "$@" \
  && echo \
  || _err "Failed to get commits between two points '$_from' and '$_to'"
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
  local _num=0

  _num="$( \
      _get_git_commits_between_two_points $_from $_to "$@" \
        | _linecount ; \
      [[ ${PIPESTATUS[0]} -eq 0 ]] || exit 1 ; \
      [[ ${PIPESTATUS[1]} -eq 0 ]] || exit 1 ; \
    )" \
  && echo "$_num" \
  || _err "Unable to get number of commits between '$_from' and '$_to'"
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
# So `git tag --contains` will return a list of tags. And that list
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
    _br="$(_get_git_branch)" || return 1
  fi

  while read _commit; do
    if _tag="$(git describe --tags --exact-match $_commit 2>/dev/null)"; then
      ruby \
        -e "_tag=\"$_tag\"" \
        -e "_br=\"$_br\"" \
        -e 'exit \
              _tag.match(/^#{_br}-([0-9]+(\.[0-9]+){1,2})(-([0-9]+))?$/) \
              ? 0 : 1
          ' \
      && echo "$_tag" && return 0
    fi
  done < \
    <(_get_git_commits_between_two_points "TheBigBang" "$_br" --until="$_ref_time")

  _err "Failed to get tag from package branch '$_br'"
}


# Return the package name from a tag
# Input
#   $1 => The current tag
#
_get_package_name_from_tag() {
  local _tag="$1"
  ruby \
    -e "_tag=\"$_tag\"" \
    -e 'if gs=_tag.match(/^(.+)-([0-9]+(\.[0-9]+){1,2})(-([0-9]+))?$/)
          puts gs[1]
        else
          STDERR.puts ":: Error: Failed to get package name from tag \"#{_tag}\""
          exit 1
        end'
}

# Return the version number from a tag
# Input
#   $1 => The current tag
#
_get_version_from_tag() {
  local _tag="$1"
  ruby \
    -e "_tag=\"$_tag\"" \
    -e 'if gs=_tag.match(/^.+-([0-9]+(\.[0-9]+){1,2})(-([0-9]+))?$/)
          puts gs[1]
        else
          STDERR.puts ":: Error: Failed to get version number from tag \"#{_tag}\""
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
    -e 'if gs=_tag.match(/^.+-([0-9]+(\.[0-9]+){1,2})(-([0-9]+))?$/)
          puts gs[3] ? gs[4] : 1
        else
          STDERR.puts ":: Error: Failed to get release number from tag \"#{_tag}\""
          exit 1
        end'
}

# Return the next tag from current tag + working branch
#
#  ---*---o-----*---*----*----*-------- thebigbang
#         |
#         \--x----*-*----x----*-----*-- package branch `foobar`
#            |    | |    |          |
#            |    | \--*-|--*----*--|-- feature branch `p_foobar-stuff`
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
#   $1 => The current tag
#   $2 => The working branch (as reference)
#
_get_next_tag_from_tag() {
  local _tag="$1"
  local _ref="${2:-HEAD}"
  local _rel=

  _rel="$(_get_number_of_git_commits_between_two_points $_tag $_ref)" \
  || return 1

  ruby \
    -e "_tag=\"$_tag\"" \
    -e "_rel=$_rel" \
    -e 'if gs=_tag.match(/^(.+)-([0-9]+(\.[0-9]+){1,2})(-([0-9]+))?$/)
          _rel += gs[4] ? gs[5].to_i : 1
          puts "#{gs[1]}-#{gs[2]}-#{_rel}"
        else
          STDERR.puts ":: Error: Failed to the next of tag \"#{_tag}\""
          exit 1
        end'
}

# Return version number from the old PKGBUILD. This is useful when
# importing the old package to our build system: immediately after
# importing we will need the version number to create the first tag.
#
# Note: If the version string has only one number, it will be ignored.
#
# Input
#   $1 => STDIN (contents of an ArchLinux PKGBUILD)
#
_get_version_from_old_PKGBUILD() {
  ruby -e "STDIN.readlines.each do |line|
    if gs = line.match(%r{^pkgver=(['\"])([0-9]+(\.[0-9]+){1,2})\1[[:space:]]*$})
      puts gs[2]; exit 0
    elsif gs = line.match(%r{^pkgver=([0-9]+(\.[0-9]+){1,2})[[:space:]]*$})
      puts gs[1]; exit 0
    end
  end
  STDERR.puts ':: Error:: Unable to read \"pkgver\" from PKGBUILD'
  exit 1"
}

# TheSLinux's version of Arch makepkg. This will check and generate
# some environment variables before invoking the real program `makepkg`.
# Note: the dash (-) hides this function from Geany symbols listing
#
# `s-makepkg` will
#
#   1. Detect the package name from working environment
#   2. Get the latest tag on the package branch
#   3. Find the next valid tag
#   4. Retrieve the version number and release number for the tag
#   5. Invoke the original `makepkg` with new environment
#
# By default, `s-makepkg` uses the latest tag from the `package branch`.
# If you want to specify an exact tag, use `PACKAGE_[REF_]TAG` instead.
# This tag `PACKAGE_REF_TAG` must exist in the git repository bc it is
# used as reference. `PACKAGE_TAG` don't need to be exist.
# If `PACKAGE_[REF_]TAG` is used, you don't need to set `PACKAGE_BASE`
# because we can retrieve it from `PACKAGE_[REF_]TAG` as in the form
#
#   PACKAGE_[REF_]TAG == PACKAGE_BASE-<version number>[-<release number>
#
# The order of these variables
#
#   1. PACKAGE_TAG      (you are at your own risk)
#   2. PACKAGE_REF_TAG  (start from the known point in the past)
#   3. PACKAGE_BASE     (+ reference tag from the current branch)
#
# Difference from the original `makepkg`
#
#   1. Package information {name, version, release} can be provided
#      externally (from the environment)
#   2. `PKGBUILD` should provide metadata and build process, it doesn't
#      contain any real data (version number, checksums,..)
#   3. The default hash is `sha512` (this's part of `pacman` though)
#   4. Can build any version of package quickly without modifying the
#      `PKGBUILD`. However, some `PKGBUILD` may only work with a limit
#      set of versions (if this is the case, we may split `PKGBUILD`
#      into parts.)
#   5. `Release number` is detected automatically
#   6. `PKGBUILD` isn't independent and it can't be used with the original
#      `makepkg` without some environment settings
#   7. Doesn't support version string that only has one number. E.g,
#      the package `xterm` or `less` only uses one number (patch number).
#      This is possibly due to history reason. This number will be converted
#      to two number forms by adding zero `0` to the original string. E.g,
#      `xterm-291-1` should read `xterm-0.291-1`.
#   8. `PACKAGE_BASE` (so `pkgbase`) is alway defined.
#
# Input
#      => PACKAGE_TAG      => the tag of new package
#      => PACKAGE_REF_TAG  => the reference tag (where the package starts)
#      => PACKAGE_BASE     => the original package branch
#   $1 => --current-tag    => print current tag and exit
#      => --next-tag       => print next tag and exit
#   $@ => pass to original `makepkg`
#
s-makepkg() {
  local _tag=
  local _ver=
  local _rel=
  local _pkg=
  local _type="--reference"

  _pkg="$(_get_package_name)" || return 1

  # If package tag is provided
  if [[ -n "$PACKAGE_TAG" ]]; then
    _type="--absolute"
    _tag="$PACKAGE_TAG"
  elif [[ -n "$PACKAGE_REF_TAG" ]]; then
    _tag="$PACKAGE_REF_TAG"
  elif ! _tag="$(_get_git_tag_on_package_branch ${_pkg})"; then
    return 1
  fi

  if [[ "$1" == "--current-tag" ]]; then
    echo "$_tag"
    return 0
  fi

  # If reference is provided, and or
  if [[ "$_type" == "--reference" ]]; then
    _tag="$(_get_next_tag_from_tag ${_tag})" || return 1
  fi

  if [[ "$1" == "--next-tag" ]]; then
    if [[ "$_type" == "--reference" ]]; then
      echo "$_tag"
    else
      _err "No reference tag as PACKAGE_TAG is provided"
    fi
    return $?
  fi

  _ver="$(_get_version_from_tag $_tag)" || return 1
  _rel="$(_get_release_from_tag $_tag)" || return 1

  :; \
    PACKAGE_BASE="$_pkg" \
    PACKAGE_RELEASE="$_rel" \
    PACKAGE_VERSION="$_ver" \
  makepkg "$@"
}

_func=""
case "${0##*/}" in
  "s-package-import") _func="import" ;;
  "s-makepkg")        _func="s-makepkg" ;;
esac

[[ -n "$_func" ]] || (( $# )) || _die "Missing arguments"

$_func "$@"
