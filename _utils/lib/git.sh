# Purpose: The heart of TBS (dealing with git tags/branches)
# Author : Anh K. Huynh
# License: GPL v2 (http://www.gnu.org/licenses/gpl-2.0.html)
# Date   : 2013 March 30th
#          2014 Apr 15th (split big files into parts)
# Home   : https://github.com/TheSLinux/buildsystem/tree/_utils

# Get the current git branch in the working directory.
# or check if a local branch does exist.
#
# Input
#   $1 => branch => A branch to check if it exist
#   $1 => empty  => Get current branch in working directory
#
_get_git_branch() {
  local _br=
  if [[ "${1:-HEAD}" != "HEAD" ]]; then
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

  case "${1-}" in
    ":feature") shift; _feature=":feature" ;;
    ":name")    shift; _feature=":name" ;;
  esac

  _feature="${_feature:-:name}"
  _tag="${PACKAGE_TAG:-${PACKAGE_REF_TAG-}}"

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

  _br="${_br:-${PACKAGE_BASE-}}"

  # Make sure there is local branch
  _br="$(_get_git_branch "$_br")" || return 1

  # We only need to check for the last case (br = <current branch>)
  awk \
    -vbr="$_br" \
    -vwd="$_wd" \
    -vfeature="$_feature" \
    'BEGIN {
      reg = sprintf("^(p_)?%s([@+#=%](.+))?$", wd);
      if (match(br, reg, m)) {
        switch(feature) {
        case ":name":
          printf("%s\n", wd);
          break;
        case ":feature":
          printf("%s\n", m[2] ? m[2] : (m[1] ? "@patch" : "="));
          break;
        }
        exit(0);
      }
      else {
        printf(":: Error: Branch \"%s\" and directory \"%s\" do not match.\n", br, wd) > "/dev/stderr";
        exit(1);
      }
    }'
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
  local _from="${1-}"; shift
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
  local _from="${1-}"; shift
  local _to="${1:-HEAD}"; shift
  local _num=0

  _num="$( \
      _get_git_commits_between_two_points $_from $_to "$@" \
        | _linecount ; \
      _is_good_pipe ; \
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
          awk \
            -vtag="$_tag" \
            -vbr="$_br" \
            'BEGIN {
              reg = sprintf("^%s-([0-9]+(\\.[0-9]+){1,3})(-([0-9]+))?$", br);
              if (tag ~ reg) print tag;
            }'
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

  case "${1-}" in
    ":version") shift; _feature=":version" ;;
    ":release") shift; _feature=":release" ;;
    ":name")    shift; _feature=":name" ;;
  esac

  _feature="${_feature:-:name}"
  _tag="${1-}"

  awk \
    -vtag="$_tag" \
    -vfeature="$_feature" \
    'BEGIN {
      if (match(tag, /^(.+)-([0-9]+(\.[0-9]+){1,3})(-([0-9]+))?$/, m)) {
        switch (feature) {
        case ":name"   : printf("%s\n", m[1]); break;
        case ":version": printf("%s\n", m[2]); break;
        case ":release": printf("%s\n", m[4] ? m[5] : 1); break;
        }
      }
      else {
        printf(":: Error: Failed to get package name from tag \"%s\"\n", tag) > "/dev/stderr";
        exit(1);
      }
    }'
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
  local _tag="${1-}"
  local _ref="${2:-HEAD}"
  local _rel=

  _rel="$(_get_number_of_git_commits_between_two_points $_tag $_ref)" \
  || return 1

  awk \
    -vtag="$_tag" \
    -vrel="$_rel" \
    'BEGIN {
      if (match(tag, /^(.+)-([0-9]+(\.[0-9]+){1,3})(-([0-9]+))?$/, m)) {
        switch(rel) {
        case 0:
          printf("%s\n", tag);
          break;
        default:
          rel += (m[4] ? m[5] : 1);
          printf("%s-%s-%s\n", m[1], m[2], rel);
        }
      }
      else {
        printf(":: Error: Failed to the next of tag \"%s\"\n", tag) > "/dev/stderr";
        exit(1);
      }
    }'
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

  : ${PACKAGE_BASE=}
  : ${PACKAGE_FEATURE=}
  : ${PACKAGE_TAG=}
  : ${PACKAGE_REF_TAG=}

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

  if [[ "${1-}" == "--current-tag" ]]; then
    echo "$_tag"
    return 0
  fi

  # If reference is provided, and or
  if [[ "$_type" == "--reference" ]]; then
    _tag="$(_get_next_tag_from_tag ${_tag})" || return 1
  fi

  if [[ "${1-}" == "--next-tag" ]]; then
    if [[ "$_type" == "--reference" ]]; then
      echo "$_tag"
    else
      _err "No reference tag as PACKAGE_TAG is provided"
    fi
    return $?
  fi

  _ver="$(_get_version_from_tag $_tag)" || return 1
  _rel="$(_get_release_from_tag $_tag)" || return 1

  if [[ "${1-}" == "--dump" ]]; then
  cat >&2 <<EOF
PACKAGE_BASE="$_pkg"
PACKAGE_RELEASE="$_rel"
PACKAGE_VERSION="$_ver"
PACKAGE_FEATURE="$_pkg_feature"
EOF
  fi

  readonly PACKAGE_BASE="$_pkg"
  readonly PACKAGE_RELEASE="$_rel"
  readonly PACKAGE_VERSION="$_ver"
  readonly PACKAGE_FEATURE="$_pkg_feature"
}

# Return the SVN revision number at the time the package is imported.
# When a package is imported, the commit message is of the form
#   Import from ABS @ <number>
# This is the first commit of the package on the package branch.
# The import process can be found under 'pkg_import.sh'
_get_svn_revision_from_the_1st_commit() {
  git log | grep 'Import from ABS @' | awk '{print $NF}'
  _is_good_pipe
}
