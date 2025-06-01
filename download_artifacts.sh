#!/bin/bash

ARTIFACTORY_URL="https://jfrog.devops.datalogic.com/artifactory"
REMOTE_REPO_PREFIX="mob-dl4490-generic"
REMOTE_REPO_SUFFIX="local"
REMOTE_BASE_PATH="mob/bsp-android/dl4490"
LOCAL_PATH="/mnt/ssd_1tb/images/4490"

LOG_FILE="/home/truongnguyen/Working/storage/log.log"

remotes=("qa")
androids=("a13" "a15")
dates=()
types=("gms" "aosp")
variants=("user" "userdebug")
firmwares=("ota.zip" "fastboot.zip")

query_jf() {
    local imageDirectory=$1
    jf rt search "${imageDirectory}/*" --include-dirs=true --recursive=false | jq -r '.[] | (.path)'
}

convert_remote_path() {
    local remote=$1

    if [[ "$remote" == */* ]]; then
        echo "${remote%/}"
    else
        echo "${REMOTE_REPO_PREFIX}-${remote}-${REMOTE_REPO_SUFFIX}/${REMOTE_BASE_PATH}"
    fi
}

# Prints every repository that holds images this script can download
list_remotes() {
    local -x JFROG_CLI_LOG_LEVEL=ERROR

    local repos=()
    mapfile -t repos < <(jf rt curl -s -XGET "/api/repositories?type=local" \
        | jq -r --arg prefix "${REMOTE_REPO_PREFIX}-" \
               --arg suffix "-${REMOTE_REPO_SUFFIX}" \
               '.[].key | select(startswith($prefix)) | select(endswith($suffix))' \
        | sort)

    if [[ ${#repos[@]} -eq 0 ]]; then
        echo "No repository matches ${REMOTE_REPO_PREFIX}-*-${REMOTE_REPO_SUFFIX}" >&2
        echo "Check the Artifactory login with: jf c show" >&2
        return 1
    fi

    echo "Remote paths on ${ARTIFACTORY_URL}"
    echo
    printf '%-10s %-16s %s\n' "NAME" "ANDROID" "REMOTE PATH"

    local listed=0
    for repo in "${repos[@]}"; do
        local name=${repo#"${REMOTE_REPO_PREFIX}-"}
        name=${name%"-${REMOTE_REPO_SUFFIX}"}

        local path="${repo}/${REMOTE_BASE_PATH}"
        local found=()
        for android in $(query_jf "$path"); do
            found+=("$(basename "$android")")
        done

        # Repositories without the bsp-android layout hold nothing to download
        [[ ${#found[@]} -eq 0 ]] && continue

        printf '%-10s %-16s %s\n' "$name" "${found[*]}" "$path"
        listed=1
    done

    if [[ $listed -eq 0 ]]; then
        echo "No repository contains ${REMOTE_BASE_PATH}" >&2
        return 1
    fi

    echo
    echo "Pass a name to --remote, for example: $(basename "$0") --remote ${remotes[0]}"
    echo "A value containing '/' is used as a full remote path instead."
}

download_jf() {
    local path_firmware=$1
    local destination=$2

    mkdir -p "$(dirname "$destination")" \
    || { echo "FAILED TO CREATE DIRECTORY: $(dirname "$destination")" && return 1; }

    jf rt download \
        --flat=true \
        --threads=8 \
        --split-count=8 \
        --retries=2 \
        --fail-no-op=true \
        "$path_firmware" "$destination"

    local rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "FAILED DOWNLOAD (jf exit ${rc}):"
    else
        echo "DOWNLOADED to:"
    fi
    echo "        $destination"

    return $rc
}



usage() {
cat <<EOF
Usage: $(basename "$0") [options]

Selects which images to download. An option takes one or more values, given as
separate words, as a comma separated list, or both:
    -a a13 a15      -a a13,a15      -a=a13,a15
When an option is omitted its default is used.

Options:
-r, --remote    qa,prod,nightly,int    Remote repositories to search
                                        (default: qa). A value containing '/'
                                        is used as a full remote path.
-l, --list-remotes                     List the remote paths --remote accepts
-a, --android   a13,a15                Android versions        (default: a13,a15)
-d, --date      YYYYMMDD[,...]         Exact build dates       (default: today)
    --from      YYYYMMDD               First date of a range   (implies --to today)
    --to        YYYYMMDD               Last date of a range    (used with --from)
-n, --daysago      N                      Last N daysago up to today
-t, --type      gms,aosp               Build types             (default: gms,aosp)
-v, --variant   user,userdebug         Build variants          (default: user,userdebug)
-f, --firmware  ota.zip,fastboot.zip   Image suffix, the part of the file name
                                        after the last '_'      (default: ota.zip,fastboot.zip)
-h, --help                             Show this help

Examples:
$(basename "$0") --list-remotes
$(basename "$0") -r prod -a a15 -d 20260827
$(basename "$0") --remote qa,nightly --daysago 7
$(basename "$0") -a a13 a15 -d 20260827 -t gms -v userdebug user -f ota.zip
$(basename "$0") -a a15 --daysago 10
$(basename "$0") --from 20260801 --to 20260827 -v userdebug
EOF
}

get_options() {
    local daysago="" 
    local date_from="" 
    local date_to=""
    while [[ $# -gt 0 ]]; do
        local arg=$1
        local opt=${arg%%=*}
        local vals=() chunk=()
        shift

        if [[ "$arg" == *=* ]]; then
            IFS=',' read -r -a vals <<< "${arg#*=}"
        else
            while [[ $# -gt 0 && "$1" != -* ]]; do
                IFS=',' read -r -a chunk <<< "$1"
                vals+=("${chunk[@]}")
                shift
            done
        fi

        case "$opt" in
            -r|--remote|-a|--android|-d|--date|-t|--type|-v|--variant|-f|--firmware|-n|--daysago|--from|--to)
                if [[ ${#vals[@]} -eq 0 ]]; then
                    echo "Missing value for option: $opt" >&2
                    return 1
                fi
                ;;
            *)
                echo "Unknown option: $opt" >&2
                usage >&2
                return 1
                ;;
        esac

        # Options that accept a single value only
        case "$opt" in
            -n|--daysago|--from|--to)
                if [[ ${#vals[@]} -gt 1 ]]; then
                    echo "Option $opt expects a single value, got: ${vals[*]}" >&2
                    return 1
                fi
                ;;
        esac

        # Remote names end up in a path, keep them free of surprises
        if [[ "$opt" == "-r" || "$opt" == "--remote" ]]; then
            for val in "${vals[@]}"; do
                if [[ ! "$val" =~ ^[A-Za-z0-9._/-]+$ ]]; then
                    echo "Invalid remote: $val" >&2
                    return 1
                fi
            done
        fi

        case "$opt" in
            -r|--remote)   remotes=("${vals[@]}") ;;
            -a|--android)  androids=("${vals[@]}") ;;
            -d|--date)     dates=("${vals[@]}") ;;
            -t|--type)     types=("${vals[@]}") ;;
            -v|--variant)  variants=("${vals[@]}") ;;
            -f|--firmware) firmwares=("${vals[@]}") ;;
            -n|--daysago)  daysago=${vals[0]} ;;
            --from)        date_from=${vals[0]} ;;
            --to)          date_to=${vals[0]} ;;
        esac
    done

    # inner function to generate dates between two given dates
    get_dates() {
        local date_from=$1
        local date_to=$2

        local dates=()
        current="$date_from"
        while [[ "$current" -le "$date_to" ]]; do
            dates+=("$current")
            current=$(date -d "$current + 1 day" +%Y%m%d)
        done
        echo "${dates[@]}"
    }

    is_date_valid() {
        local date=$1
        if [[ ! "$date" =~ ^[0-9]{8}$ ]]; then
            echo "Invalid date (expected YYYYMMDD): $date" >&2
            return 1
        fi
        return 0
    }

    # if dates are already provided, use them
    if [[ ${#dates[@]} -ne 0 ]]; then
        return 0
    fi
    
    # if daysago is provided, use it
    if [[ -n "$daysago" ]]; then
        if [[ ! "$daysago" =~ ^[0-9]+$ ]]; then
            echo "--daysago expects a number, got: $daysago" >&2
            return 1
        fi

        date_from=$(date -d "$daysago days ago" +%Y%m%d)
        date_to=$(date +%Y%m%d)

        dates=($(get_dates "$date_from" "$date_to"))
        return 0
    fi

    # if --from and --to are provided, use them
    if [[ -n "$date_from" && -n "$date_to" ]]; then
        (is_date_valid "$date_from" && is_date_valid "$date_to") || return 1
        if [[ "$date_from" -gt "$date_to" ]]; then
            echo "Invalid date range: $date_from is after $date_to" >&2
            return 1
        fi

        dates=($(get_dates "$date_from" "${date_to:-$(date +%Y%m%d)}"))
        return 0
    fi

    # if no dates are determined by any of the above methods, use today
    dates=("$(date +%Y%m%d)")
}

download() {
    local remotes=("${!1}")
    local androids=("${!2}")
    local dates=("${!3}")
    local types=("${!4}")
    local variants=("${!5}")
    local firmwares=("${!6}")

    local type_variants=()
    for type in "${types[@]}"; do
        for variant in "${variants[@]}"; do
            type_variants+=("${type}-${variant}")
        done
    done

    for remote in "${remotes[@]}"; do
        local remote_base="$(convert_remote_path "$remote")"
        echo "Searching remote path: $remote_base"

        local androids_found=($(query_jf "$remote_base"))
        if [[ ${#androids_found[@]} -eq 0 ]]; then
            echo "NOTHING FOUND at remote path (run --list-remotes for the usable ones):"
            echo "        $remote_base"
            continue
        fi

        for android in "${androids_found[@]}"; do
            if [[ ! " ${androids[@]} " =~ " $(basename "$android") " ]]; then
                continue
            fi
            echo "Found android directory: $android"
            for date in $(query_jf "${android}"); do
                if [[ ! " ${dates[@]} " =~ " $(basename "$date" | cut -d. -f4 | cut -c1-8) " ]]; then
                    continue
                fi
                echo "Found date directory: $date"
                for type_variant in $(query_jf "${date}"); do
                    if [[ ! " ${type_variants[@]} " =~ " $(basename "$type_variant") " ]]; then
                        continue
                    fi
                    echo "Found type-variant directory: $type_variant"
                    for firmware in $(query_jf "${type_variant}"); do
                        local name="$(basename "$firmware")"
                        if [[ ! " ${firmwares[@]} " =~ " ${name##*_} " ]]; then
                            continue
                        fi

                        local source="$firmware"
                        local destination="${LOCAL_PATH}/${source#${remote_base}/}"
                        echo "Try downloading:"
                        echo "        ${ARTIFACTORY_URL}/${source}"

                        if [[ -f "$destination" ]]; then
                            echo "SKIP DOWNLOAD (File already exists) in:"
                            echo "        $destination"
                        else
                            download_jf "$source" "$destination"
                        fi
                    done
                done
            done
        done
    done
}

main() {
    get_options "$@" || return 1

    echo "Datetime now: $(date)"
    echo "Checking to download images..."

    echo remotes: "${remotes[@]}"
    echo androids: "${androids[@]}"
    echo dates: "${dates[@]}"
    echo types: "${types[@]}"
    echo variants: "${variants[@]}"
    echo firmwares: "${firmwares[@]}"
    echo local path: "$LOCAL_PATH"
    echo log file: "$LOG_FILE"
    echo "----------------------------------------"

    download remotes[@] androids[@] dates[@] types[@] variants[@] firmwares[@]
}

# --help and --list-remotes only print, so they are handled before the download
# run and leave the log file of the last real run untouched.
for arg in "$@"; do
    case "$arg" in
        -h|--help)         usage; exit 0 ;;
        -l|--list-remotes) list_remotes; exit $? ;;
    esac
done

main "$@" 2>&1 | tee "$LOG_FILE"

