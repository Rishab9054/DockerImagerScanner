#!/bin/bash

# docker-push-wrapper.sh
# Place this in your PATH, named 'docker-push'

# Check if the command is trying to push an image
if [[ "$1" == "push" ]]; then
  echo "Intercepting Docker push command..."
  
  # Get the image name and tag
  IMAGE_NAME="$2"
  
  # Extract username and repository from the image name
  USERNAME=$(echo $IMAGE_NAME | cut -d'/' -f1)
  REPO=$(echo $IMAGE_NAME | cut -d'/' -f2 | cut -d':' -f1)
  TAG=$(echo $IMAGE_NAME | cut -d':' -f2)
  
  if [[ -z "$TAG" ]]; then
    TAG="latest"
  fi
  
  echo "Triggering GitHub Action for image: $USERNAME/$REPO:$TAG"
  
  # Create a Windows-compatible temporary directory
  if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    # Windows path handling
    TEMP_DIR=$(mktemp -d -p "${TEMP:-/tmp}" docker_scan.XXXXXXXX)
    # Convert to Windows path if needed
    TAR_FILE="$TEMP_DIR/image.tar"
    # Create the directory explicitly to ensure it exists
    mkdir -p "$TEMP_DIR"
  else
    # Unix systems
    TEMP_DIR=$(mktemp -d)
    TAR_FILE="$TEMP_DIR/image.tar"
  fi
  
  echo "Saving image to $TAR_FILE..."
  docker save "$IMAGE_NAME" -o "$TAR_FILE"
  
  # Check if the image was saved successfully
  if [ ! -f "$TAR_FILE" ]; then
    echo "Failed to save the Docker image to $TAR_FILE"
    echo "Checking if the image exists..."
    docker image inspect "$IMAGE_NAME" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      echo "Error: Image $IMAGE_NAME does not exist."
      exit 1
    fi
    exit 1
  fi
  
  # Use GitHub CLI to trigger a workflow
  echo "Triggering GitHub workflow..."
  gh workflow run docker-security-scan.yml -f image_name="$IMAGE_NAME" -f tar_file="$TAR_FILE"
  
  # Wait for the workflow to complete
  echo "Waiting for workflow to complete..."
  WORKFLOW_ID=$(gh run list --workflow=docker-security-scan.yml --limit=1 --json databaseId --jq '.[0].databaseId')
  
  # Poll for completion
  while true; do
    STATUS=$(gh run view $WORKFLOW_ID --json status --jq '.status')
    if [[ "$STATUS" == "completed" ]]; then
      break
    fi
    echo "Workflow status: $STATUS"
    sleep 5
  done
  
  # Check workflow conclusion
  CONCLUSION=$(gh run view $WORKFLOW_ID --json conclusion --jq '.conclusion')
  
  if [[ "$CONCLUSION" == "success" ]]; then
    echo "✅ Security scan passed! Pushing image to Docker Hub..."
    $(which docker) push "$IMAGE_NAME"
    echo "✅ Successfully pushed $IMAGE_NAME to Docker Hub"
  else
    echo "❌ Security scan failed! Image not pushed to Docker Hub."
    echo "❌ Check the workflow logs for details: https://github.com/Rishab9054/DockerImagerScanner/actions/runs/$WORKFLOW_ID"
  fi
  
  # Clean up
  rm -rf "$TEMP_DIR"
else
  # If not a push command, pass through to the real Docker command
  $(which docker) "$@"
fi