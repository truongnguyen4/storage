#!/bin/bash
#
# Clean, sync and rebuild a 4490/6690 source tree, either completely or only one module.
# Must be run on the host (not inside the build docker).
#
# Usage: ./sync_and_build.sh --src <4490|6690> [--module <kernel|qssi|vendor|all>]

set -uo pipefail

# ----------------------------------------------------------------------------
# Per source configuration, selected with --src
#   source_dir      : repo root of the source tree
#   docker_image    : same image as build_scripts/start_docker.sh
#   le_kernel_dir   : linux embedded kernel dir, mounted on kernel/kernel_platform
#   build_log       : log written by localbuild.sh with its default variant
#   <module>_groups : manifest groups synced for the module (comma separated, repo list -g)
#   <module>_flags  : module flags, accepted by both build_clean.sh and localbuild.sh
# ----------------------------------------------------------------------------

declare -A CONFIG_4490=(
   [source_dir]="${HOME}/Working/src/4490-user"
   [docker_image]="aosp-qcm4490-build-env"
   [le_kernel_dir]="chip_code/LE.UM.5.3.1/apps_proc/src/kernel-5.10/kernel_platform"
   [build_log]="logs/build_user.txt"
   [kernel_groups]="kernel"
   [kernel_flags]="--kernel"
   [qssi_groups]="qssi13,qssi15"
   [qssi_flags]="--qssi13 --qssi15"
   [vendor_groups]="vendor,qssi12"
   [vendor_flags]="--vendor"
)

declare -A CONFIG_6690=(
   [source_dir]="${HOME}/Working/src/6690-user"
   [docker_image]="aosp-qcm4490-la-40-build-env"
   [le_kernel_dir]="chip_code/LE.VM.1.2.r1/apps_proc/src/kernel-6.6/kernel_platform"
   [build_log]="logs/build_userdebug.txt"
   [kernel_groups]="kernel"
   [kernel_flags]="--kernel"
   [qssi_groups]="qssi17"
   [qssi_flags]="--qssi17"
   [vendor_groups]="luca-vendor,vendor,qssi15-la4"
   [vendor_flags]="--vendor"
)

# Projects and the local branch to check out again after sync
declare -A RESTORE_BRANCHES=(
   [build_scripts]="customize-local-build"
)

SYNC_JOBS=$(nproc)

# ----------------------------------------------------------------------------
# Values selected from the command line, filled by parse_args and load_config
# ----------------------------------------------------------------------------
SRC=""
MODULE="all"
SHOW_HELP=false

SOURCE_DIR=""
PKG_DIR=""
DOCKER_IMAGE=""
LE_KERNEL_DIR=""
BUILD_LOG=""
SYNC_GROUPS=""
CLEAN_ARGS=()
BUILD_ARGS=()

print_help() {
   echo "Usage: $0 --src <4490|6690> [--module <kernel|qssi|vendor|all>]"
   echo "Options:"
   echo "  --src [4490|6690]                     Source tree to clean, sync and build (required)"
   echo "  --module [kernel|qssi|vendor|all]     Only clean, sync and build this module (default: all)"
   echo "  --help                                Show this help message"
}

log_step() {
   echo "=========================================="
   echo "$1"
   echo "=========================================="
}

log_error() {
   echo "ERROR: $1" >&2
}

exit_on_failure() {
   log_error "Step '$1' FAILED, exit"
   exit 1
}

parse_args() {
   while [ $# -gt 0 ]; do
      case "$1" in
         --help)
            SHOW_HELP=true
            shift
            ;;
         --src)
            [ $# -gt 1 ] || { log_error "--src requires 4490 or 6690"; return 1; }
            SRC="$2"
            shift 2
            ;;
         --module)
            [ $# -gt 1 ] || { log_error "--module requires kernel, qssi, vendor or all"; return 1; }
            MODULE="$2"
            shift 2
            ;;
         *)
            log_error "Invalid option: $1"
            return 1
            ;;
      esac
   done
}

load_config() {
   [ -n "${SRC}" ] || { log_error "--src is required (see --help)"; return 1; }
   declare -p "CONFIG_${SRC}" > /dev/null 2>&1 \
      || { log_error "invalid --src: ${SRC} (expected 4490 or 6690)"; return 1; }
   local -n config="CONFIG_${SRC}"

   SOURCE_DIR="${config[source_dir]}"
   PKG_DIR="${SOURCE_DIR}/pkg"
   DOCKER_IMAGE="${config[docker_image]}"
   LE_KERNEL_DIR="${config[le_kernel_dir]}"
   BUILD_LOG="${SOURCE_DIR}/${config[build_log]}"

   if [ "${MODULE}" = "all" ]; then
      SYNC_GROUPS=""
      CLEAN_ARGS=(--all)
      BUILD_ARGS=()
      return 0
   fi

   [ -n "${config[${MODULE}_flags]+x}" ] \
      || { log_error "invalid --module: ${MODULE} (expected kernel, qssi, vendor or all)"; return 1; }

   SYNC_GROUPS="${config[${MODULE}_groups]}"
   read -ra CLEAN_ARGS <<< "${config[${MODULE}_flags]}"
   BUILD_ARGS=("${CLEAN_ARGS[@]}")
}

print_config() {
   local project restore_list=""
   for project in "${!RESTORE_BRANCHES[@]}"; do
      restore_list+="${project}:${RESTORE_BRANCHES[${project}]} "
   done

   echo "  src / module    : ${SRC} / ${MODULE}"
   echo "  source dir      : ${SOURCE_DIR}"
   echo "  pkg dir         : ${PKG_DIR}"
   echo "  docker image    : ${DOCKER_IMAGE}"
   echo "  le kernel dir   : ${LE_KERNEL_DIR}"
   echo "  build log       : ${BUILD_LOG}"
   echo "  sync groups     : ${SYNC_GROUPS:-all projects} (jobs: ${SYNC_JOBS})"
   echo "  clean args      : ${CLEAN_ARGS[*]}"
   echo "  build args      : ${BUILD_ARGS[*]:-all steps}"
   echo "  restore branches: ${restore_list}"
}

check_environment() {
   [ ! -f /.dockerenv ] || { log_error "run this script on the host, not inside docker"; return 1; }

   [ -d "${SOURCE_DIR}/.repo" ] || { log_error "not a repo root: ${SOURCE_DIR}"; return 1; }

   [ -d "${PKG_DIR}/qct" ] || { log_error "compilers dir not found: ${PKG_DIR}/qct"; return 1; }

   command -v repo > /dev/null || { log_error "'repo' command not found"; return 1; }

   docker image inspect "${DOCKER_IMAGE}" > /dev/null 2>&1 || { log_error "docker image not found: ${DOCKER_IMAGE}"; return 1; }
}

clean_output() {
   echo "build_clean.sh ${CLEAN_ARGS[*]}"
   "${SOURCE_DIR}/build_scripts/build_clean.sh" "${CLEAN_ARGS[@]}"
}

# Print the paths of the repo projects in the manifest groups SYNC_GROUPS
list_module_projects() {
   (cd "${SOURCE_DIR}" && repo list -p -g "${SYNC_GROUPS}")
}

sync_source() {
   local projects=()
   if [ -n "${SYNC_GROUPS}" ]; then
      mapfile -t projects < <(list_module_projects)
      [ ${#projects[@]} -gt 0 ] || { log_error "no repo project found in groups: ${SYNC_GROUPS}"; return 1; }
      echo "Syncing ${#projects[@]} projects of ${MODULE} (groups: ${SYNC_GROUPS})"
   else
      echo "Syncing all projects"
   fi

   (cd "${SOURCE_DIR}" && repo sync -c -j"${SYNC_JOBS}" --no-tags --force-checkout "${projects[@]}")
}

# Try every project, then fail if any branch could not be restored:
# building without the local branches (e.g. customized localbuild.sh) would give a wrong result
restore_branches() {
   local project branch failed=0
   for project in "${!RESTORE_BRANCHES[@]}"; do
      branch="${RESTORE_BRANCHES[${project}]}"
      echo "${project}: checkout ${branch}"
      if ! git -C "${SOURCE_DIR}/${project}" checkout "${branch}"; then
         log_error "cannot restore branch '${branch}' in ${project}"
         failed=1
      fi
   done
   return ${failed}
}

build_in_docker() {
   local tty_args=()
   if [ -t 0 ] && [ -t 1 ]; then
      tty_args=(-it)
   fi

   echo "docker ${DOCKER_IMAGE}: localbuild.sh ${BUILD_ARGS[*]}"
   rm -f "${BUILD_LOG}"
   docker run --rm "${tty_args[@]}" -e USER_ID="$(id -u)" -e GROUP_ID="$(id -g)" \
      -v "${SOURCE_DIR}":/aosp \
      -v "${PKG_DIR}":/pkg \
      -v "${HOME}":/home/aosp_builder \
      -v "${SOURCE_DIR}/kernel/kernel_platform":/aosp/vendor/kernel_platform \
      -v "${SOURCE_DIR}/kernel/kernel_platform":"/aosp/${LE_KERNEL_DIR}" \
      -w /aosp "${DOCKER_IMAGE}" ./build_scripts/localbuild.sh "${BUILD_ARGS[@]}"
}

check_build_result() {
   [ -f "${BUILD_LOG}" ] || { log_error "build log not found: ${BUILD_LOG}"; return 1; }
   if grep -qE "^(Build|Step) .* FAILED" "${BUILD_LOG}"; then
      log_error "build failed, see ${BUILD_LOG}"
      return 1
   fi
}

LOG_FILE=""
main() {
    parse_args "$@" || exit_on_failure "parse arguments"
    DATE=$(date +%Y%m%d)
    LOG_FILE="/home/truongnguyen/Working/storage/logs/sync_and_build_${SRC}_${MODULE}_${DATE}.log"

    if [ "${SHOW_HELP}" = true ]; then
    print_help
    exit 0
    fi

    log_step "[Load config]"
    load_config || exit_on_failure "load config"
    print_config

    log_step "[Check environment]"
    check_environment || exit_on_failure "check environment"
    log_step "OK"

    log_step "[Clean ${MODULE} build output]"
    clean_output || exit_on_failure "clean build output"
    log_step "OK"

    log_step "[Sync ${MODULE} source]"
    local sync_failed=false
    sync_source || sync_failed=true

    log_step "[Restore local branches]"
    restore_branches || exit_on_failure "restore local branches"
    log_step "OK"

    [ "${sync_failed}" = false ] || exit_on_failure "sync source"

    log_step "[Build ${MODULE} in docker]"
    build_in_docker || exit_on_failure "build in docker"
    log_step "OK"

    log_step "[Check build result]"
    check_build_result || exit_on_failure "check build result"
    log_step "OK"

    echo "${SRC} ${MODULE}: clean, sync and build completed: SUCCESSFUL"
}

main "$@" > "${LOG_FILE}" 2>&1
