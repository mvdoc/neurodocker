#!/usr/bin/env bash

# This script installs a dedicated Miniconda (not added to $PATH), installs
# ReproZip, runs `reprozip trace ...` on an arbitrary number of commands, and
# finally runs `reprozip pack`.
#
# This script accepts an arbitrary number of arguments, where each argument is
# a command to be traced. It is recommended to initialize an environment
# variable with the command string and to pass that environment variable to
# this script.

set -e
# set -x

REPROZIP_CONDA=/opt/neurodocker-reprozip-miniconda
REPROZIP_TRACE_DIR="$(mktemp -d -p $HOME neurodocker-reprozip-trace-XXXX)"
rmdir "$REPROZIP_TRACE_DIR"  # reprozip complains if directory exists.

# This log prefix is used in trace.py.
NEURODOCKER_LOG_PREFIX="NEURODOCKER (in container)"


function log_info() {
  echo "${NEURODOCKER_LOG_PREFIX}: $@"
}

function log_err() {
  echo "${NEURODOCKER_LOG_PREFIX}: $@" >&2
}

function program_exists() {
  hash "$1" 2>/dev/null;
}

function system_install() {
  if program_exists "apt-get"; then
    log_info "installing $@ with apt-get"
    apt-get update -qq
    apt-get install -yq --no-install-recommends $@
  elif program_exists "yum"; then
    log_info "installing $@ with yum"
    yum install -y -q $@
  else
    log_err "cannot install $@ (error using apt-get and then yum)."
    exit 1
  fi
}

function install_dependencies() {
  TO_INSTALL=""
  for PKG in bzip2 curl; do
    if ! program_exists $PKG; then
      TO_INSTALL="$TO_INSTALL $PKG"
    fi
  done
  if [ -n "$TO_INSTALL" ]; then
    system_install $TO_INSTALL
  fi
}

function _install_conda_reprozip() {
  CONDA_URL=https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh
  TMP_CONDA_INSTALLER=/tmp/miniconda.sh
  curl -sSL -o "$TMP_CONDA_INSTALLER" "$CONDA_URL"
  bash $TMP_CONDA_INSTALLER -b -p $REPROZIP_CONDA
  rm -f $TMP_CONDA_INSTALLER
  ${REPROZIP_CONDA}/bin/conda install -yq -n root -c vida-nyu python=3.5 reprozip
  ${REPROZIP_CONDA}/bin/conda clean -tipsy
}

function install_conda_reprozip() {
  if [ -f ${REPROZIP_CONDA}/bin/reprozip ]; then
    log_info "using installed ReproZip."
  else
    log_info "installing dedicated Miniconda and ReproZip"
    _install_conda_reprozip
  fi
}

function run_reprozip_trace() {
  cmds=("$@")
  reprozip_base_cmd="${REPROZIP_CONDA}/bin/reprozip trace -d ${REPROZIP_TRACE_DIR} --dont-identify-packages"

  for cmd in "${cmds[@]}"; do
    if [ "$cmd" == "${cmds[0]}" ]; then
        continue_=""
    else
        continue_="--continue"
    fi

    reprozip_cmd="${reprozip_base_cmd} ${continue_} ${cmd}"
    log_info "executing command: ${reprozip_cmd}"
    $reprozip_cmd
    err_code="$?"
    if [ "$err_code" != 0 ]; then
      log_err "command returned non-zero error code: $err_code"
      exit 1
    fi
  done
}

function main() {
  if [ ${#*} -eq 0 ]; then
    log_err "no arguments provided"
    exit 1
  fi

  install_dependencies
  install_conda_reprozip

  # Run reprozip trace.
  log_info "running reprozip trace command(s)"
  run_reprozip_trace "$@"

  # Run reprozip pack.
  REPROZIP_PATH_FILENAME=${REPROZIP_TRACE_DIR}/neurodocker-reprozip.rpz
  log_info "packing up reprozip experiment"
  ${REPROZIP_CONDA}/bin/reprozip pack -d ${REPROZIP_TRACE_DIR} ${REPROZIP_PATH_FILENAME}
  log_info "saved pack file within the container to"
  echo "${REPROZIP_PATH_FILENAME}"
}

main "$@"
