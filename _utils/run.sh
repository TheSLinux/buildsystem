#!/bin/bash
#
# Purpose: Various tools (See function docs.)
# Author : Anh K. Huynh
# License: GPL v2 (http://www.gnu.org/licenses/gpl-2.0.html)
# Date   : 2013 March 30th
# Home   : https://github.com/TheSLinux/buildsystem/tree/_utils
# FIXME  : Split this huge Bash script into parts (libraries)
#
# Copyright (c) 2013 Anh K. Huynh <kyanh@theslinux.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

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

# Date   : 2013 March 30th
# Purpose: Import a package from ABS to current repository
# Usage  : $0 <package> <package> <package:arch-package-name>
#
# To import a package "foobar" in the buildsystem and use a new
# package name, you can use specify the alias as this example
#
#   $0  my-theslinux-package:archlinux-package
#   $0  special-systemd:systemd
#
# The script to find the package from a list of ABS directories,
# import ABS if there is no local branch for the package, create the
# very first tag for `_makepkg` if possible. New package will start
# from `TheSmallBang` branch.
#
# Directories:
#
#   a/   : Where to store ABS packages in the structure
#             <package-1>/trunk/
#             <package-2>/trunk
#          This is because ABS is in SVN structure, and the most
#          development stuff is in the directory `/trunk/`
#
#   b/   : Similar to `a/`, but for :community packages
#
#   ./   : where to import new package; this is often the root
#          directory of the :builssystem.
#
# If you are new to our buildsystem, please try as below
#
#   $ git clone https://github.com/TheSLinux/buildsystem.git
#   $ cd buildsystem
#   $ svn checkout --depth=empty svn://svn.archlinux.org/community b
#   $ svn checkout --depth=empty svn://svn.archlinux.org/packages  a
#
# You may use the "ABS" environment to specify list of directories
# where our script looks up for the Arch packages information.
#
_import_package() {
  local _pkg="$1:"                    # package name + :
  local _apkg=":$1"                   # : + (arch) package name
  local _ds=""                        # path to Arch package/trunk
  local _dd=""                        # destination on our buildsystem
  local _rev=                         # package revision (SVN)
  local _f_readme=""                  # our README file
  local _pkgver=
  local _D_ABS="${ABS:-$PWD/a/ $PWD/b/}"

  _pkg="${_pkg%%:*}"                  # the first part, splitted by :
  _apkg="${_apkg##*:}"                # the last part, splitted by :
  _apkg="${_apkg:-$_pkg}"             # by default, _pkg  == _apkg
  _dd="$PWD/$_pkg/"

  _msg ">> Trying to import package $_pkg (from Arch '$_apkg' package) <<"

  [[ ! -d "$_dd/" ]] \
  || { _err "Directory does exist $_dd"; return 1; }

  # Find the first ABS source that contains `$_apkg`
  for _ds in $_D_ABS; do
    [[ ! -d "$_ds/$_apkg/trunk/" ]] || break
  done

  # If we don't find any $_pkg in current list of sources
  # we will try to invoke `svn update` in every source. Please note that
  # the command `svn update non-existent-package` will return 0 even if
  # the package doesn't exist in the ArchLinux's ABS system. There is
  # two ways to check if there is a package: `svn ls` and `svn update`.
  if [[ ! -d "$_ds/$_apkg/trunk/" ]]; then
    for _ds in $_D_ABS; do
      pushd "$_ds/"
      _msg "Invoking 'svn update $_apkg' in $_ds/"
      svn update "$_apkg"
      # After invoking `svn update` we need to check if the directory
      # for our package `$_apkg` does exist.
      [[ ! -d "$_ds/$_apkg/trunk" ]] || { popd; break; }
      popd
    done
  fi

  # We scan all ABS sources again to see if there is `$_apkg`
  for _ds in $_D_ABS; do
    [[ ! -d "$_ds/$_apkg/trunk/" ]] || break
  done

  _ds="$_ds/$_apkg/trunk/"

  # If we don't find it at all, return with error
  [[ -d "$_ds/" ]] \
  || { _err "Directory not found  $_ds"; return 1; }

  # We nee to be on the master before creating new branch
  git co master \
  && git co -b "$_pkg" "TheSmallBang" \
  || {
    _err "Failed to switch to 'master' or to create new branch $_pkg"
    return 1
  }

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

      # README contents
      {
        echo "Import from ArchLinux's ABS package '$_apkg'"
        echo ""
        svn info \
          | grep -E "^(URL|Revision):"
      } \
        > "$_f_readme"
    }

    popd
  }

  # Generate git commit. Please note that the commit messge contains
  # the revision number that will be used in the future.
  git add "$_dd" \
  && git commit "$_pkg/" -m"$_pkg: Import from ABS $_apkg @ $_rev" \
  && git co master \
  && _fix_the_1st_tag_on_package_branch "$_pkg" \
  || { _err "Something wrong with git repository"; return 1; }
}

# Import all packages provided in the arguments
_import_packages() {
  while (( $# )); do
    _import_package $1
    shift
  done
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
  if [[ -n "$1" && "$1" != "HEAD" ]]; then
    git show-branch "$1" >/dev/null \
    && echo "$1" \
    || return 1
  else
    _br="$(git rev-parse --abbrev-ref HEAD)" \
    && echo "$_br" \
    || return 1
  fi
}

# Get the package name/feature from the working directory / branch.
#
# The common rules (TheSmallBang) says that the package branch would be
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
#   FEATURE BRANCH   | FEATURE BRANCH | FEATURE | CONFLICT
#   -----------------+----------------+----------+---------
#   p_foobar         |                | patch   | yes
#   p_foobar+feature | foobar+feature | feature | ?
#   p_foobar#feature | foobar#feature | feature | ?
#   p_foobar=feature | foobar=feature | feature | (noop)
#   p_foobar%feature | foobar%feature | feature | no
#   p_foobar@feature | foobar@feature | feature | yes
#
# Input
#   => Working directory is a package directory (a must)
#   => PACKAGE_BASE (env. var.) is set (optional)
#   => PACKAGE_REF_TAG (env. var.) is set (optional)
#   => PACKAGE_RAG is set (optional)
#   => PACKAGE_FEATURE is set (optional)
#
#   $1 => :feature => return the feature string from the branch name
#                     (prefixed by a modifier @, %, =, # or +)
#   $1 => :name    => return the package name
#   $1 => <empty>  => as :name
#
_get_package_name() {
  local _wd="$(basename $PWD)"
  local _br=
  local _tag=
  local _feature=

  case "$1" in
    ":feature") shift; _feature=":feature" ;;
    ":name")    shift; _feature=":name" ;;
  esac

  _feature="${_feature:-:name}"

  # Check if tag is provided
  _tag="${PACKAGE_TAG:-}"
  _tag="${_tag:-$PACKAGE_REF_TAG}"

  if [[ "$_feature" == ":feature" && -n "$PACKAGE_FEATURE" ]]; then
    case "${PACKAGE_FEATURE:0:1}" in
      "@"|"="|"#"|"+"|"%")
          echo  "$PACKAGE_FEATURE" ;;
      *)  echo "@$PACKAGE_FEATURE" ;;
    esac
    return 0
  fi

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
    -e "_feature=$_feature" \
    -e 'gs = _br.match(%r{^(p_)?#{_wd}([@+#=%](.+))?$})
        unless gs
          STDERR.puts ":: Error: Branch \"#{_br}\" and directory \"#{_wd}\" do not match"
          exit 1
        end
        puts \
        case _feature
          when :name then _wd
          when :feature then
            gs[2] ? gs[2] : (gs[1] ? "@patch" : "=")
        end
      ' \
  || return 1
}

# Return the feature of the current feature branch
# This is almost as same as (_get_package_name), but it returns a feature
# Input
#   => the current working branch
#   => the current package name
#
_get_package_feature() {
  _get_package_name ":feature"
}

# Return a list of commits between two points.
# The starting point will not be listed in the output.
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

  git rev-list "$_from".."$_to" "$@" \
  || _err "Failed to get commits between two points '$_from' and '$_to', opts => $@"
}

# Return the number of items from (_get_git_commits_between_two_points)
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
      _is_good_pipe || exit 1 ; \
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
# do that, we will (1) list all commits since `TheSmallBang`, and (2) get
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
#         This must be `package branch`, not a `feature branch`.
#         E.g, `uim-vi` is valid, but `p_uim-vi@foobar` is not valid.
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

  _br="$(_get_git_branch "$_br")" || return 1

  while read _commit; do
    _tag="$( \
      git tag --points-at $_commit \
      | while read _tag; do
          ruby \
            -e "_tag=\"$_tag\"" \
            -e "_br=\"$_br\"" \
            -e 'exit \
                  _tag.match(/^#{_br}-([0-9]+(\.[0-9]+){1,3})(-([0-9]+))?$/) \
                  ? 0 : 1
              ' \
          && echo "$_tag"
        done \
      | sort \
      | tail -1 \
      )"
    [[ -z "$_tag" ]] || { echo "$_tag"; return 0 ; }
  done < \
    <(_get_git_commits_between_two_points "TheSmallBang" "$_br" --until="$_ref_time")

  _err "Failed to get tag from package branch '$_br'"
}

# Return the package name/version/tag from a tag string
# Input
#   $1 => :version => get the version number
#   $1 => :release => get release number
#   $1 => :name    => get package number
#   $1 => <empty>  => as :name
#   $@ => the tag
#
_get_package_name_from_tag() {
  local _tag=
  local _feature=

  case "$1" in
    ":version") shift; _feature=":version" ;;
    ":release") shift; _feature=":release" ;;
    ":name")    shift; _feature=":name" ;;
  esac

  _feature="${_feature:-:name}"
  _tag="$1"

  ruby \
    -e "_tag=\"$_tag\"" \
    -e "_feature=$_feature" \
    -e 'if gs=_tag.match(/^(.+)-([0-9]+(\.[0-9]+){1,3})(-([0-9]+))?$/)
          case _feature
            when :name    then puts gs[1]
            when :version then puts gs[2]
            when :release then puts gs[4] ? gs[5] : 1
          end
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
  _get_package_name_from_tag ":version" "$@"
}

# Return the release number of a tag
# Input
#   $1 => The current tag
_get_release_from_tag() {
  _get_package_name_from_tag ":release" "$@"
}

# Return the current package tag from the working directory
_get_current_tag() {
  local _br=
  _br="$(_get_package_name)" || return 1
  _get_git_tag_on_package_branch $_br
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
    -e 'if gs=_tag.match(/^(.+)-([0-9]+(\.[0-9]+){1,3})(-([0-9]+))?$/)
          if _rel == 0
            puts _tag
          else
            _rel += gs[4] ? gs[5].to_i : 1
            puts "#{gs[1]}-#{gs[2]}-#{_rel}"
          end
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
    if gs = line.match(%r{^pkgver=(['\"])([0-9]+(\.[0-9]+){1,3})\1[[:space:]]*$})
      puts gs[2]; exit 0
    elsif gs = line.match(%r{^pkgver=([0-9]+(\.[0-9]+){1,3})[[:space:]]*$})
      puts gs[1]; exit 0
    end
  end
  STDERR.puts ':: Error:: Unable to read \"pkgver\" from PKGBUILD'
  exit 1"
}

# Check if there is a tag that indicates time when package is imported
# from the ABS. This first tag is important bc it helps `_makepkg`.
#
# Strategy
#
#   1. Check if the branch is a package branch: the name of the branch
#      <branch> shoud lead to the file <branch>:<branch>/PKGBUILD
#   2. Find the first commit of the <branch>
#   3. Check if there is tag at the commit
#      1. If there is tag, but it isn't an annotation tag -> fix it
#      2. If there is not a tag
#         1. Find the version from PKGBUILD
#         2. Create new annotatag from that version
#
# Input
#   $1 => The branch to check (this should be a package branch)
#
_fix_the_1st_tag_on_package_branch() {
  local _br="${1:-HEAD}"
  local _commit=
  local _tag=
  local _pkgver=

  _br="$(_get_git_branch "$_br")" || return 1
  git show "$_br:$_br/PKGBUILD" >/dev/null \
  || {
    _err "The branch '$_br' is not a package branch"
    return 1
  }
  _commit="$( \
      git log --pretty="format:%H" "TheSmallBang".."$_br" -- | tail -1 ;\
      _is_good_pipe || exit 1 \
    )" \
  || return 1

  # Because the file `PKGBUILD` does exist in the branch, there is
  # no way that `_commit` is empty (as `TheSmallBang` and our branch
  # have a the same current commit.

  if _tag="$(git describe --tags --exact-match "$_commit" 2>/dev/null)"; then
    _tag="$(_get_package_name_from_tag "$_tag")" || return 1
    [[ "$_tag" != "$_br" ]] || return 0
    _err "Tag was created but it doesn't match package branch '$_br'"
    return 1
  fi

  _pkgver="$(
      git show "$_commit":$_br/PKGBUILD \
        | _get_version_from_old_PKGBUILD ; \
      _is_good_pipe || exit 1 \
    )" \
  || return 1

  git tag -s -a \
    -m"The original source from the ABS" \
    "$_br-$_pkgver" "$_commit"
}

# TheSLinux's version of Arch makepkg. This will check and generate
# some environment variables before invoking the real program `makepkg`.
# Note: the dash (-) hides this function from Geany symbols listing
#
# Difference from the original `makepkg`
#
# 1. Package information {name, version, release} can be provided
#    externally (from the environment)
# 2. `PKGBUILD` should provide metadata and build process, it doesn't
#    contain any real data (version number, checksums,..)
# 3. The default hash is `sha512` (this's part of `pacman` though)
# 4. Can build any version of package quickly without modifying the
#    `PKGBUILD`. However, some `PKGBUILD` may only work with a limit
#    set of versions (if this is the case, we may split `PKGBUILD`
#    into parts.)
# 5. `Release number` is detected automatically
# 6. `PKGBUILD` isn't independent and it can't be used with the original
#    `makepkg` without some environment settings
# 7. Doesn't support version string that only has one number. E.g,
#    the package `xterm` or `less` only uses one number (patch number).
#    This is possibly due to history reason. This number will be converted
#    to two number forms by adding zero `0` to the original string. E.g,
#    `xterm-291-1` should read `xterm-0.291-1`.
# 8. `PACKAGE_BASE` (so `pkgbase`) is alway defined.
# 9. `PACKAGE_FEATURE` helps to provide package name with any special
#    feature, without creating "official branch". We just need to
#    create a feature branch and `_makepkg` will use the branch name
#    as `PACKAGE_FEATURE`, and will append the string to name of the
#    final output package. It also helps to modify the variables
#    `conflicts`, `provides`,... on-the-fly.
#    `PACKAGE_FEATURE` must be prefixed with an modifier ([@%=+#]).
#    See `_get_package_name` for details.
#
_makepkg() {
  _s_env || return 1
  PACKAGE_BASE="$PACKAGE_BASE" \
  PACKAGE_RELEASE="$PACKAGE_RELEASE" \
  PACKAGE_VERSION="$PACKAGE_VERSION" \
  PACKAGE_FEATURE="$PACKAGE_FEATURE" \
  makepkg "$@"
}

# Check out The{Small,Big}Bang to local working directory
# that is required to start and build new packages
#
# NOTE: TheBigBang should not be used for new package -- 2013 Aug 3rd
_git_bang_bang() {
  { git branch | grep -q 'TheSmallBang' ; } \
  || git branch "TheSmallBang" "origin/TheSmallBang"
}

# `_s_env` will
#
# 1. Detect the package name from working environment
# 2. Get the latest tag on the package branch
# 3. Find the next valid tag
# 4. Retrieve the version number and release number for the tag
#
# By default, `_s_env` uses the latest tag from the `package branch`.
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
# 1. PACKAGE_TAG      (you are at your own risk)
# 2. PACKAGE_REF_TAG  (start from the known point in the past)
# 3. PACKAGE_BASE     (+ reference tag from the current branch)
#
# Input
#      => PACKAGE_TAG      => the tag of new package
#      => PACKAGE_REF_TAG  => the reference tag (where the package starts)
#      => PACKAGE_BASE     => the original package branch
#      => PACKAGE_FEATURE  => special feature of the package
#   $1 => --current-tag    => print current tag and exit
#      => --next-tag       => print next tag and exit
#      => --dump           => print results to STDERR
#
# Output
#   error || PACKAGE_{BASE, VERSION, RELEASE, FEATURE}
#
# History
#
# `_s_env` is taken from the original implementation of the `_makepkg`
#  function. Because the output of `_s_env` is useful and may be used
# in different context, we move the first part to a this `_s_env`.
#
_s_env() {
  local _tag=
  local _ver=
  local _rel=
  local _pkg=
  local _pkg_feature=
  local _type="--reference"

  _git_bang_bang || return 1
  _pkg="$(_get_package_name)" || return 1
  _pkg_feature="$(_get_package_feature)" || return 1

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

  if [[ "$1" == "--dump" ]]; then
  cat >&2 <<EOF
PACKAGE_BASE="$_pkg"
PACKAGE_RELEASE="$_rel"
PACKAGE_VERSION="$_ver"
PACKAGE_FEATURE="$_pkg_feature"
EOF
  fi

  PACKAGE_BASE="$_pkg"
  PACKAGE_RELEASE="$_rel"
  PACKAGE_VERSION="$_ver"
  PACKAGE_FEATURE="$_pkg_feature"
}

# Execute the `get_update` function from PKGBUILD. If the function
# does not exist, an error will occur. Assume that we are in right
# directory (this is true if `_s_env` runs  well) that has PKGBUILD
_get_update() {
  _s_env || return 1
  unset "get_update"
  source "PKGBUILD" || return 127
  get_update
}

# Reset some environments' variables and load the PKGBUILD file in
# the current working directory, or return error (127).
#
# Input
#   _s_env
#
# Output
#   New working environment
#
# FIXME: Add PACKAGE_CONFLICT_TYPE support
#
_pkgbuild_load() {
  _s_env || return 1

  if [[ -z "${PACKAGE_FEATURE}" || -z "${PACKAGE_FEATURE:1}" ]]; then
    _FEATURE_STRING=""
  else
    _FEATURE_STRING="${PACKAGE_FEATURE}"
  fi

  # FIXME: We should not mirror code like this. Need another way to
  # FIXME: patch `makepkg` and make code clean.
  unset pkgname pkgbase pkgver pkgrel epoch pkgdesc url license groups provides
  unset md5sums replaces depends conflicts backup source install changelog build
  unset makedepends optdepends options noextract

  pkgver="${PACKAGE_VERSION:-}"
  pkgrel="${PACKAGE_RELEASE:-}"
  pkgbase="${PACKAGE_BASE:-}"

  pkgname="${pkgname:-$pkgbase}"

  shopt -u extglob # FIXME: why?
  source "PKGBUILD" || return
  if [[ -n "${_FEATURE_STRING}" && -f "PKGBUILD${_FEATURE_STRING}" ]]; then
    source "PKGBUILD${_FEATURE_STRING}" || return
  fi
  shopt -s extglob # FIXME: why?

  if [[ "${PACKAGE_FEATURE:0:1}" == "@" ]]; then
    conflicts=("${conflicts[@]}" "$pkgname")
    provides=("${provides[@]}" "$pkgname")
  fi
}

# Print list of source files required by PKGBUILD
_pkgbuild_sources() {
  _pkgbuild_load || return
  for __ in "${source[@]}"; do
    echo "${__}"
  done
}

# Return the list of sources on #theslinux mirror.
# This function will load `PKGBUILD if `PACKAGE_BASE is not defined.
_pkgbuild_s_sources() {
  local _sources=()
  local _basename=
  local _uri=

  _pkgbuild_load || return

  for __ in "${source[@]}"; do
    echo "${__}" | grep -q '://' \
    || {
      _sources+=("${__}")
      continue
    }
    echo "${__}" | grep -Eq '\.sig$' && continue
    echo "${__}" | grep -Eq '\.asc$' && continue
    echo "${__}" | grep -q '::' \
    && {
      _basename="${__%%::*}"
    } \
      || _basename="${__##*/}"

    _uri="http://f.theslinux.org/s/${PACKAGE_BASE}/${_basename}"
    _sources+=("${_uri}" "${_uri}.asc")
  done

  echo "${_sources[@]}"
}

# This script will read the PKGBUILD from the current build environment
# and print YAML contents that describe some basic information of the
# package. The primary purpose is to gather information from packages
# quicly and simple. We also build our own hierachy of dependencies.
#
# Input
#   Current build environment that's detected by `_s_env`
#
# Output
#   YAML string should be checked by a 3rd party method
#   Always return 0. See also `_pkgbuild_to_yaml_with_check`
#
# FIXME: Add PACKAGE_CONFLICT_TYPE support
#
_pkgbuild_to_yaml() {
  _pkgbuild_load || return

  cat <<EOF
---
$PACKAGE_BASE:
  version: "$PACKAGE_VERSION"
  description: "$pkgdesc"
  feature: "$PACKAGE_FEATURE"
  url: "$url"
  license: "${license[@]}"
EOF

  [[ -z "${pkgname}" ]] \
    && echo "  packages:" \
    && for _u in "${pkgname[@]}"; do echo "  - $_u"; done

  [[ -n "${sources}" ]] \
    && echo "  sources:" \
    && for _u in "${source[@]}"; do echo "  - $_u"; done

  [[ -n "${conflicts}" ]] \
    && echo "  conflicts:" \
    && for _u in "${conflicts[@]}"; do echo "  - $_u"; done

  [[ -n "${provides}" ]] \
    && echo "  provides:" \
    && for _u in "${provides[@]}"; do echo "  - $_u"; done

  [[ -n "${replaces}" ]] \
    && echo "  replaces:" \
    && for _u in "${replaces[@]}"; do echo "  - $_u"; done

  [[ -n "${makedepends}" ]] \
    && echo "  makedepends:" \
    && for _u in "${makedepends[@]}"; do echo "  - $_u"; done

  [[ ! -f "$install" ]] \
    && [[ -f "${PACKAGE_BASE}.install" ]] \
    && install="${PACKAGE_BASE}.install" \
    || install=""

  # The contents of `install` script will be shipped with the package
  # FIXME: If a sub-package provides its own `install` script we can not
  # FIXME: detect the script here. Should find another way.
  [[ -z "$install" ]] \
  || {
    echo "  install: |"
    cat "$install" | awk '{printf("    %s\n", $0)}'
  }

  : 'This function often returns successfully'
}

# Return the SVN revision number at the time the package is imported.
# When a package is imported, the commit message is of the form
#   Import from ABS @ <number>
# This is the first commit of the package on the package branch.
_get_svn_revision_from_the_1st_commit() {
  git log | grep 'Import from ABS @' | awk '{print $NF}'
  _is_good_pipe
}

# Check the output of `_pkgbuild_to_yaml` with Ruby/YAML
# The output of this command is often more compact that the original
# output of `_pkgbuild_to_yaml`.
#
# Input
#   As same as `_pkgbuild_to_yaml`
#
# Output
#   error || Valid YAML file
#
# FIXME: A valid PKGBUILD should containn some basic fields like
# FIXME: package name, version, build script,... The check should know
# FIXME: this and return error if there is any missing field
#
# FIXME: What happends if we have 10,000 packages to check!?
#
_pkgbuild_to_yaml_with_check() {
  _pkgbuild_to_yaml "$@" \
  | ruby -ryaml -e "puts YAML.dump(YAML.load(STDIN))"
}

# main routine #########################################################

unset _func || _die "Unable to update '_func' variable"

case "${0##*/}" in
  "s-import-package") _func="_import_packages" ;;
  "s-makepkg")        _func="_makepkg" ;;
esac

[[ -n "$_func" ]] || (( $# )) || _die "Missing arguments"

$_func "$@"
