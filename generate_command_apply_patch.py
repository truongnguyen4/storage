import os
import json
import subprocess
from pathlib import Path
import shutil

HELP = "--help"
ABORT = "--abort"

JAZZ_ID = "211853"                                                                              # Need to be updated
LEVEL = "2025-12"
ANDROID_VERSION = "android-13.0.0_r1"                                                           # Need to be updated

# For get bulletin information
PATH_SPL = f"/home/truongnguyen/Working/storages/bulletin/2025-12-20251104T020129Z-1-001/{LEVEL}"       # Need to be updated

FILE_BULLETIN = f"{LEVEL}-android-bulletin-partner-preview.json"
PATH_FILE_BULLETIN = os.path.join(PATH_SPL, FILE_BULLETIN)

FOLDER_PATCHES = f"{LEVEL}-android-bulletin-partner-preview-patches"
PATH_FOLDER_PATCHES = os.path.join(PATH_SPL, FOLDER_PATCHES)

# For reset log file
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PATH_REPORT_INFO = os.path.join(CURRENT_DIR, "log_info.txt")
PATH_REPORT_RESULT = os.path.join(CURRENT_DIR, "log_result.txt")
PATH_FOLDER_FAILED_PATCHES = os.path.join(CURRENT_DIR, "failed_folder")

# For apply automatically
PATH_AOSP = "/home/truongnguyen/Working/src/sx5"

def writeToFile(lines, file, type):
    with open(file, type) as f:
        for line in lines:
            f.write(line + "\n")

def run_bash_command(path, bash_command):
    if not os.path.exists(path):
        return False
    try:
        result = subprocess.run(
            bash_command,
            shell=True,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            cwd=path
        )
        return True
    except subprocess.CalledProcessError as error:
        return False

def prepare():
    # Create folder failed patches if not exist
    if os.path.exists(PATH_FOLDER_FAILED_PATCHES):
        shutil.rmtree(PATH_FOLDER_FAILED_PATCHES)
    os.makedirs(PATH_FOLDER_FAILED_PATCHES, exist_ok=True)

    # Create the log info file if it not exist
    for path in [PATH_REPORT_INFO, PATH_REPORT_RESULT]:
        with open(path, "w") as f:
            f.write("")
    
    # Check if the required paths exist
    for path in [PATH_FOLDER_PATCHES, PATH_FILE_BULLETIN]:
        if not os.path.exists(path):
            print(f"Path does not exist: {path}")
            return False

    return True

def parse_preview_json_file():
    # read preview json file
    with open(PATH_FILE_BULLETIN, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as e:
            print(f"Failed to parse JSON: {e}")
            return ""

def read_preview_json_file(preview_json_file):
    CVEs = []
    repos = []

    vulnerabilities = [vulnerability for vulnerability in preview_json_file["vulnerabilities"] if all(k in vulnerability for k in ["CVE", "patch_files", "android_id", "subcomponent", "tech_details", "fix_details"])]
    for vulnerability in vulnerabilities:
        cve_id = vulnerability["CVE"]
        android_id = vulnerability["android_id"]
        message = "\n".join([
            f"[jazz:{JAZZ_ID}] {cve_id}",
            "",
            "Subcomponent",
            vulnerability["subcomponent"],
            "",
            "Technical details",
            vulnerability["tech_details"],
            "",
            "Fix details",
            vulnerability["fix_details"],
            ""
        ])
        
        # Get the patch files that correspond to the target project
        patches = []
        for path in [patch_files for patch_files in vulnerability["patch_files"] if ANDROID_VERSION in patch_files]:
            partitions = path.split("/")
            info = {
                "repo" : "/".join(partitions[3:-1]),
                "name" : partitions[-1],
                "path" : path
            }
            patches.append(info)
            
            if info["repo"] not in repos:
                repos.append(info["repo"])

        CVEs.append({
            "cve_id": cve_id,
            "android_id": android_id,
            "message": message,
            "patches": patches,
        })

    return CVEs, repos

def get_primary_log(CVEs, repos):
    logs = [
        "\n============== Information ==============",
        f"[1] ANDROID_VERSION: {ANDROID_VERSION}",
        f"[2] JAZZ_ID: {JAZZ_ID}",
        # "\nTotal patches found: " + str(len(set_patches)),
        "\nList of impacted repos:",
    ]

    # Add a list of all unique repos
    logs.extend(list(" " * 4 + repo for repo in repos))

    for id, CVE in enumerate(CVEs, start=1):
        logs.extend([
            "\n" + "=" * 40 + f" Index - {id} " + "=" * 40,
            f"cve_id: {CVE['cve_id']}",
            f"android_id: {CVE['android_id']}"
        ])
        logs.extend(list(" " * 4 + info["path"] for info in [info for info in CVE["patches"]]))
        logs.append("Message:\n" + CVE["message"])

    return logs

def apply_patch(path_repo, path_patch, message):
    return False
    # cmd_apply_patch = f'git am {path_patch}'
    # cmd_abort = "git am --abort"
    # cmd_amend_message = f'git commit --amend -m "{message}"'

    # # if apply patch command by "git am" is not successful, then abort
    # if not run_bash_command(path_repo, cmd_apply_patch):
    #     run_bash_command(path_repo, cmd_abort)
    #     return False

    # # Modify commit message
    # run_bash_command(path_repo, cmd_amend_message)
    # return True

def apply_all_patches(CVEs):
    logs = []
    for cve in CVEs:
        for info in cve["patches"]:
            path_repo = os.path.join(PATH_AOSP, "LINUX/android", info["repo"])
            path_patch = os.path.join(PATH_FOLDER_PATCHES, info["path"])
            result = apply_patch(path_repo, path_patch, cve["message"])
            if result is False:
                # Write failed log
                logs.extend([
                    "\n" + "-" * 40 + f" {cve['cve_id']} " + "-" * 40,
                    f"Path Patch: {path_patch}",
                    f"Result: {'Success' if result else 'Failed or Skipped'}",
                ])
                # copy failed patches to specific folder to apply manually
                path_failed_patch = PATH_FOLDER_FAILED_PATCHES + "/" + info["repo"] + "/" + info["name"]
                Path(path_failed_patch).parent.mkdir(parents=True, exist_ok=True)

                with open(path_patch, "rb") as src, open(path_failed_patch, "wb") as dst:
                    dst.write(src.read())

    return logs

if __name__ == "__main__":
    if prepare() is False:
        print("Preparation failed. Exiting.")
        exit(1)

    json_data = parse_preview_json_file()
    if not json_data:
        print("No valid preview JSON file found. Exiting.")
        exit(1)

    CVEs, repos = read_preview_json_file(json_data)

    logs = get_primary_log(CVEs, repos)
    writeToFile(logs, PATH_REPORT_INFO, "w")

    logs = apply_all_patches(CVEs)
    writeToFile(logs, PATH_REPORT_RESULT, "w")
