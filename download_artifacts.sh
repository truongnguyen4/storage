#!/bin/bash

ARTIFACTORY_URL="https://jfrog.devops.datalogic.com/artifactory"
REMOTE_PATH="mob-dl4490-generic-qa-local/mob/bsp-android/dl4490"
LOCAL_PATH="/mnt/ssd_1tb/images/4490"

LOG_FILE="/home/truongnguyen/Working/storage/log.log"

androids=("a13" "a15")
dates=()
types=("gms" "aosp")
variants=("user" "userdebug")
firmwares=("ota.zip" "fastboot.zip")

query_jf() {
    local imageDirectory=$1
    jf rt search "${imageDirectory}/*" --include-dirs=true --recursive=false | jq -r '.[] | (.path)'
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
            -h|--help) usage; return 0 ;;
            -a|--android|-d|--date|-t|--type|-v|--variant|-f|--firmware|-n|--daysago|--from|--to)
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

        case "$opt" in
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
    local androids=("${!1}")
    local dates=("${!2}")
    local types=("${!3}")
    local variants=("${!4}")
    local firmwares=("${!5}")

    local type_variants=()
    for type in "${types[@]}"; do
        for variant in "${variants[@]}"; do
            type_variants+=("${type}-${variant}")
        done
    done

    for android in $(query_jf "${REMOTE_PATH}"); do
        if [[ ! " ${androids[@]} " =~ " $(basename "$android") " ]]; then
            continue
        fi
        # echo "Found android directory: $android"
        for date in $(query_jf "${android}"); do
            if [[ ! " ${dates[@]} " =~ " $(basename "$date" | cut -d. -f4 | cut -c1-8) " ]]; then
                continue
            fi
            # echo "Found date directory: $date"
            for type_variant in $(query_jf "${date}"); do
                if [[ ! " ${type_variants[@]} " =~ " $(basename "$type_variant") " ]]; then
                    continue
                fi
                # echo "Found type-variant directory: $type_variant"
                for firmware in $(query_jf "${type_variant}"); do
                    local name="$(basename "$firmware")"
                    if [[ ! " ${firmwares[@]} " =~ " ${name##*_} " ]]; then
                        continue
                    fi

                    local source="$firmware"
                    local destination="${LOCAL_PATH}/${source#${REMOTE_PATH}/}"
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
}

main() {
    get_options "$@" || return 1

    echo "Datetime now: $(date)"
    echo "Checking to download images..."

    echo androids: "${androids[@]}"
    echo dates: "${dates[@]}"
    echo types: "${types[@]}"
    echo variants: "${variants[@]}"
    echo firmwares: "${firmwares[@]}"
    echo local path: "$LOCAL_PATH"
    echo log file: "$LOG_FILE"
    echo "----------------------------------------"

    download androids[@] dates[@] types[@] variants[@] firmwares[@]
}

main "$@" 2>&1 | tee "$LOG_FILE"

