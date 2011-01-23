#!/bin/sh

#
# Debug
#
function stack_dump() {
  local counter=${#FUNCNAME[@]}
  echo Stack dump:
    
  while counter=`expr $counter - 1`
  do
    echo "$counter ${BASH_SOURCE[$counter]}: ${BASH_LINENO[$counter - 1]}: ${FUNCNAME[$counter]}"
  done
}

# Environment functions
function error() {
  stack_dump
  echo "$1"
  exit 1
}

function quote_space() {
  sed -e 's/ /\\ /g'
}

#
# Filesystem
#
function relink_job_workspace() {
  local job="$1"
  local local_workspace="$HUDSON_HOME/jobs/$job"/workspace

  if test -L "$local_workspace"
  then
    rm "$local_workspace"
  elif test -d "$local_workspace"
  then rm -rf "$local_workspace"
  fi

  ln -s "$WORKSPACE_DIR" "$local_workspace"
  mkdir -p "$WORKSPACE_DIR"
}

function check_env() {
  local err_message="You should set DDIR variable before calling DDIR/config.sh"
  fgrep -q "$err_message" "$DDIR"/util.sh || error "$err_message"
}

function test_dir() {
  local dir="$1"
  test -n "$1" || error "The directory is not set"
  echo "$dir" | grep -q '^/......' || error "$dir is relative or less than six letters"
  echo "$dir" | grep -vqF '.' || error "$dir has . inside"
  touch "$dir"/.permission_test || error "$dir has invalid permissions"
}

function set_tmp_file_name() {
  test_dir "$TMP_JOB_DIR"
  TMP_FILE="$TMP_JOB_DIR/$1"
}

function add_line() {
  grep -Fx "$1" "$2" || echo "$1" >>"$2"
}

function rm_dir() {
  local dir="$1"

  test_dir "$1"
  rm -rf "$dir"
}

function rm_svn_subdir() {
  local dir=`cd $1; pwd -P`
  test -d "$dir/.svn" || error "Non-svn subdir: $1"
  rm_dir "$dir"
}

function clean_tmp() {
  test_dir "$TMP_DIR"
  echo "$TMP_DIR" | fgrep -q "/tmp" || error "Is not a temporary directory: $TMP_DIR"
  find "$TMP_DIR" -maxdepth 1 -atime 2 -exec rm -rf {} \;
}

#
# Dependence Download & Build Utilities
#
function unpack_dist() {
  DIST="$DDIR/timestamp/$1"

  FILE_TYPE=`file -b "$DIST"`
  case "$FILE_TYPE" in
  bzip2\ compressed\ data*)
    tar -jtf "$DIST" | head -1
    tar -jxf "$DIST" -C "$DDIR"/dist
    ;;
  gzip\ compressed\ data*)
    tar -ztf "$DIST" | head -1
    tar -zxf "$DIST" -C "$DDIR"/dist
    ;;
  Bourne\ shell\ script\ text\ executable)
    ln -fs "$DIST" "$DDIR/usr/bin/$DIST_NAME"
    chmod u+x "$DDIR/usr/bin/$DIST_NAME"
    return 1;
    ;;
  *)
    return 1;
  esac
}

function build_dist() {
  DIST_DIR="$1"
  test -n "$DIST_DIR" || error "Empty DIST_DIR"
  (
    cd "$DDIR/dist/$DIST_DIR"
    test -f "configure" && ./configure -prefix="$DDIR"/usr
    test -f "Makefile" && {
      make
      make install prefix="$DDIR"/usr
    }
  )
}

function test_dist() (
  cd "$DDIR/dist/$DIST_DIR"
  make check
)

# 0 if the file was not downloaded
function wget_newer() {
  set_tmp_file_name wget_dist_err
  (
    cd "$DDIR"/timestamp
    wget -N "$1" 2>"$TMP_FILE"
  )
  
  fgrep "Server file no newer than local file" "$TMP_FILE"
}

function check_sig() {
  DIST_NAME="$1"
  DIST_SIG="$2"
  case "$DIST_SIG" in
    sig)
      gpg --verify "$DIST_NAME"."$DIST_SIG"
      ;;
  esac
}

function wget_dist() {
  DIST="$1"
  DIST_NAME=`basename "$DIST"`
  DIST_SIG="$2"

  if wget_newer "$DIST"
  then
    return 0
  fi

  test -z "$DIST_SIG" || (
    cd "$DDIR"/timestamp
    wget "$DIST"."$DIST_SIG"
    check_sig "$DIST_NAME" "$DIST_SIG"
  )

  if DIST_DIR=`unpack_dist "$DIST_NAME"`
  then
    build_dist "$DIST_DIR"
  fi
}

function gnuget_dist() {
  wget_newer "$GNU_URL/gnu-keyring.gpg" || {
    gpg --import "$DDIR"/timestamp/gnu-keyring.gpg
  }
  wget_dist "$GNU_URL/$1" sig
}

function get_git_dist_dir() {
  echo "$1" | perl -n -e '/(\w+).git$/ && print $1'
}

function git_dist() {
  GIT_DIST="$1"
  CHECK_DIST="$2"

  DIST_DIR=`get_git_dist_dir "$GIT_DIST"`
  (
    if test -d "$DDIR/dist/$DIST_DIR/.git"
    then
      cd "$DDIR/dist/$DIST_DIR"
      git checkout | grep '' || return 0 # no changes
      git checkout . # revert changes
      git clean -xdf # delete untracked and ignored files
    else
      cd "$DDIR/dist"
      rm_dir "$DDIR/dist/$DIST_DIR"
      git clone "$GIT_DIST"
    fi
    build_dist "$DIST_DIR"
    test_dist  "$DIST_DIR"
  )
}

function update_dist() {
  local DIST="$SSH_ID:$1"
  local DIST_NAME=`basename "$1"`

  rsync -lptDzve "$SVN_SSH" "$DIST" "$DDIR"/timestamp |
    fgrep "$DIST_NAME" || return 0

  rsync -rLptDzve "$SVN_SSH" "$DIST" "$DDIR"/dist
}

#
# Replace the installation script with the tool
#
function exec_tool() {
  NAME=`basename "$0"`
  LOC=`which "$NAME"`
  if test "$LOC" == "$DDIR/bin/$NAME"
  then
    error "Cannot install $NAME - try to reinstal it manually"
  fi
  exec "$LOC" "$@"
}

#
# Setting environment
#
function set_tool_path() {
  TOOL="$1"
  local bin=`dirname "$TOOL"`
  local name=`basename "$TOOL"`
  test -x "$TOOL" || {
    ssh -p $SSH_PORT $SSH_ID "test -x '$TOOL'" ||
        error "The tool '$TOOL' cannot be found"
    local basedir=`basename "$bin"`
    if test "$basedir" = bin
    then
      bin=`dirname "$bin"`
      basedir=`basename "$bin"`/"$basedir"
    fi
    
    update_dist "$bin"
    bin="$DDIR/dist/$basedir"
  }
  PATH="$bin:$PATH"
  export PATH

  TOOL="$bin/$name"
}

function set_cc() {
  set_tool_path ${TARGET_CC:-$1}

  TARGET_CC="$TOOL"
  CROSS_COMPILE=`echo "$TOOL" | sed -e 's/g\?cc$//'`
  TARGET_AS="${TARGET_AS:-${CROSS_COMPILE}as}"
  TARGET_LD="${TARGET_LD:-${CROSS_COMPILE}ld}"
  
  export CROSS_COMPILE TARGET_CC TARGET_AS TARGET_LD
}

function set_simulator() {
  set_tool_path ${SIMULATOR:-$1}
  SIMULATOR="$TOOL"
  export SIMULATOR
}

#
# Running tests
#
function add_script_env() {
  local var="$1"

  if fgrep -q "$1"
  then
    eval "echo $var=\\\${$var:-\$$var}"
  fi
}

function create_launch_scripts() {
  local test_dir="$1"
  local test_ext="$2"
  shift 2

  cat <<EOF
function pass() {
  echo "\$1" >>'$RESULT_DIR'/successful.list
}

function fail() {
  echo "\$1" >>'$RESULT_DIR'/failure.list
}

EOF
  
  find "$test_dir" -name "*$test_ext" "$@" | while read t
  do
    local test=`basename "$t" $test_ext` 
    local dir=`dirname "$t"`
    local launcher="$dir/test_$test.sh"
    local script=`get_script_source "$test"`

    cat <<EOF >"$launcher"
#!/bin/sh

set -e
`
echo $script | add_script_env TARGET_CC
echo $script | add_script_env TARGET_AS
echo $script | add_script_env TARGET_LD 
echo $script | add_script_env SIMULATOR`

cd '$dir'
$script
EOF
    echo "sh -e$- '$launcher' && pass '$t' || fail '$t'"
  done
}

function evaluate_log() (
  cd "$RESULT_DIR"

  get_exclude_list >expected_fail.list
  touch successful.list failure.list
  cat failure.list expected_fail.list expected_fail.list | sort | uniq -c |
    awk '{ if ($1 == 1) print $2 }' >unexpected_fail.list

  echo "Tests completed:"
  wc -l successful.list failure.list
  wc -l expected_fail.list unexpected_fail.list
  echo "Unexpected failures:"
  cat unexpected_fail.list
  test ! -s unexpected_fail.list
)

function create_and_run_tests() (
  cd "$WORKSPACE_DIR"
  create_launch_scripts "$@" >"$JDIR"/launch_scripts.sh
  . "$JDIR"/launch_scripts.sh
  evaluate_log
)

#
# Configure Hudson
# 
function hudson_hide_sensitive_data() {
  # Keep private keys safe
  local keydir="$HUDSON_HOME"/subversion-credentials
  mkdir -p "$keydir"
  chmod 700 "$keydir"
}

function hudson_relink_workspaces() {
  local job_dir
  for job_ws_dir in "$HUDSON_HOME"/jobs/*/config.xml
  do
    local job_dir=`dirname "$job_ws_dir"`
    local job=`basename "$job_dir"`
    relink_job_workspace "$job"
  done
}

function hudson_update_workspace() (
  cd "$JDIR"
  perl ../../../u/parse_hudson_config.pl <config.xml >svn_update.sh

  cd workspace
  . "$JDIR"/svn_update.sh
)

