#!/bin/bash

# docker-push-wrapper.sh
# Place this in your PATH, named 'docker-push'

# Check if the command is trying to push an image
if [[ "$1" == "push" ]]; then
  echo "Intercepting Docker push command..."
  
  # Get the image name and tag
  IMAGE_NAME="$2"
  
  # Check if the image exists locally
  if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "Error: Image $IMAGE_NAME does not exist locally."
    exit 1
  fi
  
  echo "Triggering GitHub Action for image: $IMAGE_NAME"
  
  # Create a temporary repository for this run
  TEMP_REPO="temp-scan-repo-$(date +%s)"
  mkdir -p $TEMP_REPO
  
  # Save the image to a tar file
  echo "Saving image $IMAGE_NAME to a tar file..."
  docker save "$IMAGE_NAME" -o "$TEMP_REPO/image.tar"
  
  # Create a Dockerfile that simply loads the image
  cat > "$TEMP_REPO/Dockerfile" << EOF
FROM scratch
ADD image.tar /
EOF
  
  # Create an archive of the temp repository
  echo "Creating archive of the image..."
  tar -czf temp-repo.tar.gz $TEMP_REPO
  
  # Push to GitHub repository as a commit
  echo "Pushing image data to GitHub..."
  # Add the files to git
  git -C "$TEMP_REPO" init
  git -C "$TEMP_REPO" add .
  git -C "$TEMP_REPO" config user.email "auto@example.com"
  git -C "$TEMP_REPO" config user.name "Docker Scanner"
  git -C "$TEMP_REPO" commit -m "Temporary image scan for $IMAGE_NAME"
  
  # Push to a temporary branch in the repository
  TEMP_BRANCH="temp-scan-branch-$(date +%s)"
  git -C "$TEMP_REPO" branch -M $TEMP_BRANCH
  
  # Get the remote URL
  REPO_URL=$(gh repo view --json url -q .url)
  git -C "$TEMP_REPO" remote add origin $REPO_URL
  GH_TOKEN=$(gh auth token)
  git -C "$TEMP_REPO" -c http.extraHeader="Authorization: Bearer $GH_TOKEN" push -u origin $TEMP_BRANCH
  
  # Use GitHub CLI to trigger a workflow
  echo "Triggering GitHub workflow..."
  gh workflow run docker-security-scan.yml -f image_name="$IMAGE_NAME" -f branch_name="$TEMP_BRANCH"
  
  # Wait for the workflow to complete
  echo "Waiting for workflow to complete..."
  sleep 3 # Give GitHub API time to register the new run
  WORKFLOW_ID=$(gh run list --workflow=docker-security-scan.yml --limit=1 --json databaseId --jq '.[0].databaseId')
  
  if [[ -z "$WORKFLOW_ID" ]]; then
    echo "Error: Could not get workflow run ID. Please check your GitHub CLI configuration."
    exit 1
  fi
  
  echo "Monitoring workflow run ID: $WORKFLOW_ID"
  
  # Poll for completion
  while true; do
    STATUS=$(gh run view $WORKFLOW_ID --json status --jq '.status' 2>/dev/null)
    if [[ "$STATUS" == "completed" ]]; then
      break
    fi
    echo "Workflow status: $STATUS"
    sleep 5
  done
  
  # Check workflow conclusion
  CONCLUSION=$(gh run view $WORKFLOW_ID --json conclusion --jq '.conclusion')
  
  # Clean up the temporary repository
  rm -rf $TEMP_REPO
  git push origin --delete $TEMP_BRANCH || echo "Failed to delete temporary branch, it will be cleaned up later"
  
  if [[ "$CONCLUSION" == "success" ]]; then
    echo "✅ Security scan passed! Pushing image to Docker Hub..."
    $(which docker) push "$IMAGE_NAME"
    echo "✅ Successfully pushed $IMAGE_NAME to Docker Hub"
  else
    echo "❌ Security scan failed! Image not pushed to Docker Hub."
    echo "❌ Check the workflow logs for details: https://github.com/Rishab9054/DockerImagerScanner/actions/runs/$WORKFLOW_ID"
  fi
else
  # If not a push command, pass through to the real Docker command
  $(which docker) "$@"
fi