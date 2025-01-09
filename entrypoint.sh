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
TERRAFORM_OUT_DIR="./module"
TERRAFORM_CMD="terraform -chdir=$TERRAFORM_OUT_DIR"
TERRAFORM_VARS="-var-file=tfvars.json"
OUTPUTS_FILE="${TERRAFORM_OUT_DIR}/outputs.json"

# Generate module configuration
# generate-tf-config is a script in the final module.
generate-tf-config

$TERRAFORM_CMD init

if [[ $ACTION == "Apply" ]]; then
    if [[ $DRY_RUN == "True" ]]; then
        $TERRAFORM_CMD plan -out=plan $TERRAFORM_VARS
        if [ -f "validate_plan.py" ]; then
            $TERRAFORM_CMD show -json $TERRAFORM_OUT_DIR/plan > $TERRAFORM_OUT_DIR/plan.json
            python3 validate_plan.py "$TERRAFORM_OUT_DIR"/plan.json
        fi
    elif [[ $DRY_RUN == "False" ]]; then
        $TERRAFORM_CMD apply -auto-approve $TERRAFORM_VARS
        $TERRAFORM_CMD output -json > $OUTPUTS_FILE
        if [ -f "post_checks.py" ]; then
            python3 post_checks.py $OUTPUTS_FILE
        fi
    fi
elif [[ $ACTION == "Destroy" ]]; then
    if [[ $DRY_RUN == "True" ]]; then
        $TERRAFORM_CMD plan -destroy $TERRAFORM_VARS
    elif [[ $DRY_RUN == "False" ]]; then
        # Maybe the keys should be disabled instead of removed?
        $TERRAFORM_CMD destroy -auto-approve $TERRAFORM_VARS
    fi
fi
