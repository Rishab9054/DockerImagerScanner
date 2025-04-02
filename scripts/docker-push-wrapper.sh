#!/bin/bash

# docker-push-wrapper.sh
# Place this in your PATH, named 'docker-push'

# Extract the image name (remove the 'push' if it was accidentally included)
if [[ "$1" == "push" ]]; then
  IMAGE_NAME="$2"
else
  IMAGE_NAME="$1"
fi

echo "Intercepting Docker push command..."
echo "Triggering GitHub Action for image: $IMAGE_NAME"

# Check if the image exists locally
if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "Error: Image $IMAGE_NAME does not exist locally."
  exit 1
fi

# Create a temporary branch name
TEMP_BRANCH="temp-scan-branch-$(date +%s)"

# Create a temporary directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR" || exit 1

# Initialize a git repository
git init
git config user.email "auto@example.com"
git config user.name "Docker Scanner"

# Create a simple Dockerfile that uses the image
echo "FROM $IMAGE_NAME" > Dockerfile

# Commit the Dockerfile
git add Dockerfile
git commit -m "Temporary scan for $IMAGE_NAME"
git branch -M "$TEMP_BRANCH"

# Get the GitHub repository URL using GitHub CLI
REPO_URL=$(gh repo view --json url -q .url)
if [[ -z "$REPO_URL" ]]; then
  echo "Error: Could not get GitHub repository URL. Make sure you're authenticated with GitHub CLI."
  exit 1
fi

# Push to the repository
git remote add origin "$REPO_URL"
GH_TOKEN=$(gh auth token)
git -c http.extraHeader="Authorization: Bearer $GH_TOKEN" push -u origin "$TEMP_BRANCH"

# Trigger the workflow
echo "Triggering GitHub workflow..."
gh workflow run docker-security-scan.yml -f image_name="$IMAGE_NAME" -f branch_name="$TEMP_BRANCH"

# Wait for the workflow to start
echo "Waiting for workflow to start..."
sleep 5

# Find the run ID of the latest workflow run
WORKFLOW_RUN=$(gh run list --workflow=docker-security-scan.yml --branch="$TEMP_BRANCH" --limit=1 --json databaseId,status,conclusion --jq '.[0]')
WORKFLOW_ID=$(echo "$WORKFLOW_RUN" | jq -r '.databaseId')

if [[ -z "$WORKFLOW_ID" || "$WORKFLOW_ID" == "null" ]]; then
  echo "Error: Could not get workflow run ID. Please check your GitHub CLI configuration."
  exit 1
fi

echo "Monitoring workflow run ID: $WORKFLOW_ID"

# Poll for completion
while true; do
  WORKFLOW_RUN=$(gh run view "$WORKFLOW_ID" --json status,conclusion --jq '.')
  STATUS=$(echo "$WORKFLOW_RUN" | jq -r '.status')
  
  if [[ "$STATUS" == "completed" ]]; then
    break
  fi
  echo "Workflow status: $STATUS"
  sleep 10
done

# Check workflow conclusion
CONCLUSION=$(echo "$WORKFLOW_RUN" | jq -r '.conclusion')

# Clean up
cd ~
rm -rf "$TEMP_DIR"
gh api -X DELETE "repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/git/refs/heads/$TEMP_BRANCH" || echo "Failed to delete temporary branch, it will be cleaned up later"

if [[ "$CONCLUSION" == "success" ]]; then
  echo "✅ Security scan passed! Pushing image to Docker Hub..."
  docker push "$IMAGE_NAME"
  echo "✅ Successfully pushed $IMAGE_NAME to Docker Hub"
else
  echo "❌ Security scan failed! Image not pushed to Docker Hub."
  echo "❌ Check the workflow logs for details: $(gh repo view --json url -q .url)/actions/runs/$WORKFLOW_ID"
fi