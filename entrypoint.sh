#!/usr/bin/env bash
set -e

# Use /credentials as AWS credentials file if it exists
test -f /credentials && export AWS_SHARED_CREDENTIALS_FILE="/credentials"

if [[ -z "$AWS_SHARED_CREDENTIALS_FILE" ]]; then
    echo "Either AWS_SHARED_CREDENTIALS_FILE or /credentials file must be set"
    exit 1
fi

export DRY_RUN=${DRY_RUN:-"True"}
export ACTION=${ACTION:-"Apply"}
export LOCAL_STATE=${LOCAL_STATE:-"True"}

if [[ $DRY_RUN != "True" ]] && [[ $DRY_RUN != "False" ]]; then
    echo "Invalid DRY_RUN option: $DRY_RUN. Must be 'True' or 'False'"
    exit 1
fi

if [[ $ACTION != "Apply" ]] && [[ $ACTION != "Destroy" ]]; then
    echo "Invalid ACTION option: $ACTION. Must be 'Apply' or 'Destroy'"
    exit 1
fi

echo "Starting: ACTION=$ACTION with DRY_RUN=$DRY_RUN"

# WORK directory. Work is mounted as a volume to share "work" across all containers.
export WORK=${WORK:-"/work"}
mkdir -p "$WORK"
echo "Using WORK directory: $WORK"

# Terraform output options
export TF_CLI_ARGS=${TF_CLI_ARGS:-"-no-color"}

# The terraform configuration to run.
export TERRAFORM_MODULE_SRC_DIR=${TERRAFORM_MODULE_SRC_DIR:-"./module"}

# Working directory where the SRC module will be copied.
TMP_DIR=$(mktemp -d)
export TMP_DIR
export TERRAFORM_MODULE_WORK_DIR=${TERRAFORM_MODULE_WORK_DIR:-"${TMP_DIR}/module"}
echo "Using TERRAFORM_MODULE_WORK_DIR directory: ${TERRAFORM_MODULE_WORK_DIR}"

# Variables used by external-resources io to generate the required configuration
export TF_VARS_FILE=${TF_VARS_FILE:-"${TERRAFORM_MODULE_WORK_DIR}/terraform.tfvars.json"}
export BACKEND_TF_FILE=${BACKEND_TF_FILE:-"${TERRAFORM_MODULE_WORK_DIR}/backend.tf"}
export VARIABLES_TF_FILE=${VARIABLES_TF_FILE:-"${TERRAFORM_MODULE_WORK_DIR}/variables.tf"}

# Terraform will take the module path as a working directory
export TERRAFORM_CMD="terraform -chdir=$TERRAFORM_MODULE_WORK_DIR"

# the vars file path within the module directory
export TERRAFORM_VARS="-var-file=${TF_VARS_FILE}"

export PLAN_FILE="${TMP_DIR}/plan"
export PLAN_FILE_JSON="${TMP_DIR}/plan.json"

# Outputs file is read by the outputs handling container under the /work path.
export OUTPUTS_FILE="${WORK}/output.json"

LOCK="-lock=true"
if [[ $DRY_RUN == "True" ]]; then
    LOCK="-lock=false"
fi


function validate_generate_tf_config() {
    local f_path
    f_path=$(command -v generate-tf-config)
    if [[ -z "$f_path" || ! -x "$f_path" ]]; then
        echo "generate-tf-config must be an executable file and be findable in the system path"
        exit 1
    fi
}

function create_working_directory() {
    cp -a "${TERRAFORM_MODULE_SRC_DIR}" "${TERRAFORM_MODULE_WORK_DIR}"
}

function run_hook() {
    local HOOK_NAME="$1"
    shift
    local HOOK_DIR="./hooks"
    local HOOK_SCRIPT=""

    # Possible extensions for the hook scripts
    local EXTENSIONS=("sh" "py")

    if [ ! -d "$HOOK_DIR" ]; then
        # no hook directory
        return 0
    fi

    # Search for a valid hook script
    for EXT in "${EXTENSIONS[@]}"; do
        if [ -x "${HOOK_DIR}/${HOOK_NAME}.${EXT}" ]; then
            HOOK_SCRIPT="${HOOK_DIR}/${HOOK_NAME}.${EXT}"
            break
        fi
    done

    if [ -z "$HOOK_SCRIPT" ]; then
        # no hook script
        return 0
    fi

    set +e
    echo "Running hook: $HOOK_NAME"
    "$HOOK_SCRIPT" "$@"
    local HOOK_STATUS=$?
    set -e

    if [[ $HOOK_STATUS -ne 0 ]]; then
        if [[ $HOOK_STATUS -eq 42 ]]; then
            # to early exit as success, skip all remaining steps
            exit 0
        fi
        exit $HOOK_STATUS
    fi
}

function init() {
    run_hook "pre_init"
    $TERRAFORM_CMD init
    run_hook "post_init"
}


function plan() {
    run_hook "pre_plan"
    PLAN_EXTRA_OPTIONS=""
    if [[ $ACTION == "Destroy" ]]; then
        PLAN_EXTRA_OPTIONS="-destroy"
    fi
    # shellcheck disable=SC2086
    $TERRAFORM_CMD plan ${PLAN_EXTRA_OPTIONS} -out="${PLAN_FILE}" ${TERRAFORM_VARS} ${LOCK}
    $TERRAFORM_CMD show -json "${PLAN_FILE}" > "${PLAN_FILE_JSON}"
    run_hook "post_plan"
}

function apply() {
    run_hook "pre_apply"
    if [[ $ACTION == "Apply" ]] && [[ $DRY_RUN == "False" ]]; then
        $TERRAFORM_CMD apply "${PLAN_FILE}"
        $TERRAFORM_CMD output -json > "$OUTPUTS_FILE"
        run_hook "post_output"
    elif [[ $ACTION == "Destroy" ]] && [[ $DRY_RUN == "False" ]]; then
        # shellcheck disable=SC2086
        $TERRAFORM_CMD destroy -auto-approve ${TERRAFORM_VARS}
    fi
    run_hook "post_apply"
}

function fetch_terraform_state() {
    run_hook "pre_fetch_terraform_state"
    if [[ $DRY_RUN == "True" ]] && [[ $LOCAL_STATE == "True" ]]; then
        echo "Using local terraform state for dry-run mode"
        # Use local state for dry-run mode
        local tf_state="${WORK}/terraform.tfstate"
        $TERRAFORM_CMD state pull > "${tf_state}"
        cat - > "${BACKEND_TF_FILE}" <<EOF
terraform {
  backend "local" {
    path = "${tf_state}"
  }
}
EOF
        # changing the backend needs a re-init
        $TERRAFORM_CMD init -reconfigure
    fi
    run_hook "post_fetch_terraform_state"
}

validate_generate_tf_config
create_working_directory
run_hook "pre_run"
# Generate module configuration
# generate-tf-config is a script in the final module.
# It generates the terraform backend file and the vars file
# into the module directory
generate-tf-config
init
fetch_terraform_state
plan
apply
run_hook "post_run"
