#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Default values for environment variables
DOCKER_IMAGE_URL=${DOCKER_IMAGE_URL:-nginx:latest}
TOKEN=${TOKEN:-8c2ad1b3-d18c-4e71-86dd-273660a14a4c}
# GIT_REF=${GIT_REF:-test123}
RUN_ID=${RUN_ID:-}

# Parse command-line options
while getopts u:c:p:s:a:i: flag
do
    case "${flag}" in
        u) USERNAME=${OPTARG};;
        c) CP_URL=${OPTARG};;
        p) PROJECT_NAME=${OPTARG};;
        s) SERVICE_NAME=${OPTARG};;
        a) ARTIFACTORY_NAME=${OPTARG};;
        i) IS_PUSH=${OPTARG};;
        *) echo "Invalid option: -${OPTARG}" 1>&2; exit 1;;
    esac
done

# Ensure all critical environment variables are set
if [[ -z "$DOCKER_IMAGE_URL" || -z "$TOKEN" ]]; then
    echo "Critical environment variables DOCKER_IMAGE_URL or TOKEN are not set."
    echo "Please set these before running the script."
    exit 1
fi

# Determine GIT_REF based on CI/CD environment variables if not set
if [ -z "$GIT_REF" ]; then
    if [ ! -z "$GITHUB_REF" ]; then
        # Extract the last part after '/'
        GIT_REF=${GITHUB_REF##*/}
    elif [ ! -z "$GIT_COMMIT" ]; then
        GIT_REF=$GIT_COMMIT  # Common in Jenkins; usually this is a commit SHA
    elif [ ! -z "$CI_COMMIT_REF_NAME" ]; then
        GIT_REF=$CI_COMMIT_REF_NAME  # GitLab CI; usually just the branch or tag name
    elif [ ! -z "$BITBUCKET_COMMIT" ]; then
        GIT_REF=$BITBUCKET_COMMIT  # Bitbucket Pipelines; usually this is a commit SHA
    elif [ ! -z "$CODEBUILD_RESOLVED_SOURCE_VERSION" ]; then
        GIT_REF=$CODEBUILD_RESOLVED_SOURCE_VERSION  # AWS CodeBuild; usually this is a commit SHA
    else
        echo "GIT_REF is not set and could not be determined from the environment."
        exit 1
    fi
fi

# Determine RUN_ID based on CI/CD environment variables if not set
if [ -z "$RUN_ID" ]; then
    if [ ! -z "$GITHUB_RUN_ID" ]; then
        RUN_ID=$GITHUB_RUN_ID
    elif [ ! -z "$BUILD_ID" ]; then
        RUN_ID=$BUILD_ID  # Common in Jenkins
    elif [ ! -z "$CI_PIPELINE_ID" ]; then
        RUN_ID=$CI_PIPELINE_ID  # GitLab CI
    elif [ ! -z "$BITBUCKET_BUILD_NUMBER" ]; then
        RUN_ID=$BITBUCKET_BUILD_NUMBER  # Bitbucket Pipelines
    elif [ ! -z "$CODEBUILD_BUILD_ID" ]; then
        RUN_ID=$CODEBUILD_BUILD_ID  # AWS CodeBuild
    fi
fi

# Path to facetsctl binary
BIN_PATH="$(which facetsctl)"

# Ensure facetsctl is executable
if [ ! -x "$BIN_PATH" ]; then
    echo "facetsctl is not installed or not executable. Please install facetsctl and try again."
    exit 1
fi

# Print all variable values
echo "Username: $USERNAME"
echo "CP_URL: $CP_URL"
echo "Project Name: $PROJECT_NAME"
echo "Service Name: $SERVICE_NAME"
echo "Artifactory Name: $ARTIFACTORY_NAME"
echo "Is Push: $IS_PUSH"
echo "Docker Image URL: $DOCKER_IMAGE_URL"
echo "Token: $TOKEN"
echo "GIT_REF: $GIT_REF"
echo "RUN_ID: $RUN_ID"
echo "Bin Path: $BIN_PATH"

# Login using facetsctl
$BIN_PATH login -u "$USERNAME" -t "$TOKEN" -f "$CP_URL"
if [ $? -ne 0 ]; then
    echo "facetsctl login failed."
    exit 1
fi

# Initialize artifact
$BIN_PATH artifact init -p "$PROJECT_NAME" -s "$SERVICE_NAME" -a "$ARTIFACTORY_NAME"
if [ $? -ne 0 ]; then
    echo "facetsctl artifact init failed."
    exit 1
fi

# Push artifact if required
if [ "$IS_PUSH" == "true" ]; then
    $BIN_PATH artifact push -d "$DOCKER_IMAGE_URL"
    if [ $? -ne 0 ]; then
        echo "facetsctl artifact push failed."
        exit 1
    fi
fi

# Register artifact
$BIN_PATH artifact register -t GIT_REF -v "$GIT_REF" -i "$DOCKER_IMAGE_URL" -r "$RUN_ID"
if [ $? -ne 0 ]; then
    echo "facetsctl artifact register failed."
    exit 1
fi

echo "facetsctl operations completed."
