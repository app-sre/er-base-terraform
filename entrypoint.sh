#!/usr/bin/env bash
set -e

# Use /credentials as AWS credentials file if it exists
test -f /credentials && export AWS_SHARED_CREDENTIALS_FILE="/credentials"

if [[ -z "$AWS_SHARED_CREDENTIALS_FILE" ]]; then
    echo "Either AWS_SHARED_CREDENTIALS_FILE or /credentials file must be set"
    exit 1
fi

DRY_RUN=${DRY_RUN:-"True"}
ACTION=${ACTION:-"Apply"}

if [[ $DRY_RUN != "True" ]] && [[ $DRY_RUN != "False" ]]; then
    echo "Invalid DRY_RUN option: $DRY_RUN. Must be 'True' or 'False'"
    exit 1
fi

if [[ $ACTION != "Apply" ]] && [[ $ACTION != "Destroy" ]]; then
    echo "Invalid ACTION option: $ACTION. Must be 'Apply' or 'Destroy'"
    exit 1
fi

echo "Starting: ACTION=$ACTION with DRY_RUN=$DRY_RUN"

# Terraform output options
export TF_CLI_ARGS=${TF_CLI_ARGS:-"-no-color"}

# The base terraform configuration to run
export TERRAFORM_MODULE_DIR=${TERRAFORM_MODULE_DIR:-"./module"}

# Directory where the temporary files will be created
export WORK_DIR=${$MODULE_WORK_DIR:-"./work"}

# Terraform will take the module path as a working directory
export TERRAFORM_CMD="terraform -chdir=$TERRAFORM_MODULE_DIR"

# the vars file path within the module directory
export TERRAFORM_VARS="-var-file=tfvars.json"

export PLAN_FILE="$WORK_DIR/plan"
export PLAN_FILE_JSON="$WORK_DIR/plan.json"
export OUTPUTS_FILE="$WORK_DIR/output.json"

LOCK="-lock=true"
if [[ $DRY_RUN == "True" ]]; then
    LOCK="-lock=false"
fi


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

    # Export variables for hooks
    export DRY_RUN

    echo "Running hook: $HOOK_NAME"
    "$HOOK_SCRIPT" "$@"
}

function init() {
    $TERRAFORM_CMD init
}


function plan() {
    PLAN_EXTRA_OPTIONS=""
    if [[ $ACTION == "Destroy" ]]; then
        PLAN_EXTRA_OPTIONS="-destroy"
    fi
    $TERRAFORM_CMD plan ${PLAN_EXTRA_OPTIONS} -out=${PLAN_FILE} ${TERRAFORM_VARS} ${LOCK}
    $TERRAFORM_CMD show -json ${PLAN_FILE} > ${PLAN_FILE_JSON}
    run_hook "post_plan" ${PLAN_FILE_JSON}
}

function apply() {
    if [[ $ACTION == "Apply" ]] && [[ $DRY_RUN == "False" ]]; then
        $TERRAFORM_CMD apply -auto-approve ${PLAN_FILE}
    elif [[ $ACTION == "Destroy" ]] && [[ $DRY_RUN == "False" ]]; then
        $TERRAFORM_CMD destroy -auto-approve ${PLAN_FILE}
    fi
    run_hook "post_apply"
}


# Generate module configuration
# generate-tf-config is a script in the final module.
# It generates the terraform backend file and the vars file
# into the module directory
generate-tf-config

run_hook "pre_run"
init
plan
apply
run_hook "post_run
