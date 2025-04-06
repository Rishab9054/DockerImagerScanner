#!/bin/bash

# docker-secure-push.sh - A wrapper around docker push that triggers GitHub Actions

# Configuration
GITHUB_REPO="your-username/your-repo"
GITHUB_TOKEN_ENV="GITHUB_TOKEN"  # Store your GitHub token in this env variable
GITHUB_API="https://api.github.com"

# Check if GitHub token is set
if [ -z "${!GITHUB_TOKEN_ENV}" ]; then
    echo "Error: GitHub token not found. Please set the ${GITHUB_TOKEN_ENV} environment variable."
    exit 1
fi

# Parse arguments to extract the image name
if [ $# -lt 1 ]; then
    echo "Usage: $0 image[:tag]"
    exit 1
fi

IMAGE_NAME=$1
echo "🔍 Processing image: ${IMAGE_NAME}"

# Extract repository and tag
REPO_NAME=$(echo ${IMAGE_NAME} | cut -d':' -f1)
TAG=$(echo ${IMAGE_NAME} | grep ':' | cut -d':' -f2 || echo "latest")

echo "📦 Repository: ${REPO_NAME}"
echo "🏷️ Tag: ${TAG}"

# Create a unique workflow run ID
RUN_ID=$(date +%s)

# Trigger GitHub workflow
echo "🚀 Triggering security scan workflow..."
RESPONSE=$(curl -s -X POST \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Authorization: token ${!GITHUB_TOKEN_ENV}" \
    -H "Content-Type: application/json" \
    ${GITHUB_API}/repos/${GITHUB_REPO}/dispatches \
    -d '{
        "event_type": "docker-scan-request",
        "client_payload": {
            "image_name": "'"${REPO_NAME}"'",
            "image_tag": "'"${TAG}"'",
            "run_id": "'"${RUN_ID}"'"
        }
    }')

if [ $? -ne 0 ]; then
    echo "❌ Failed to trigger workflow"
    echo "${RESPONSE}"
    exit 1
fi

echo "⏳ Workflow triggered successfully. Run ID: ${RUN_ID}"
echo "⏳ Waiting for scan results..."

# Poll for workflow completion
MAX_TRIES=30
COUNT=0
WORKFLOW_STATUS="pending"

while [ "${WORKFLOW_STATUS}" = "pending" ] && [ ${COUNT} -lt ${MAX_TRIES} ]; do
    sleep 10
    COUNT=$((COUNT+1))
    
    # Get the status file from a predefined location in your repo
    STATUS=$(curl -s -H "Authorization: token ${!GITHUB_TOKEN_ENV}" \
        "${GITHUB_API}/repos/${GITHUB_REPO}/contents/scan-results/${RUN_ID}.json" | \
        grep -o '"content":"[^"]*"' | cut -d':' -f2 | tr -d '"' | base64 --decode 2>/dev/null)
    
    if [ ! -z "${STATUS}" ]; then
        # Parse the JSON response
        WORKFLOW_STATUS=$(echo ${STATUS} | grep -o '"status":"[^"]*"' | cut -d':' -f2 | tr -d '"')
        
        if [ "${WORKFLOW_STATUS}" = "success" ]; then
            echo "✅ Security scan passed!"
            echo "🚀 Pushing image to Docker Hub..."
            docker push ${IMAGE_NAME}
            echo "✅ Image successfully pushed to Docker Hub!"
            exit 0
        elif [ "${WORKFLOW_STATUS}" = "failure" ]; then
            VULNERABILITIES=$(echo ${STATUS} | grep -o '"vulnerabilities":\[[^]]*\]' | cut -d':' -f2)
            echo "❌ Security scan failed! Vulnerabilities found:"
            echo "${VULNERABILITIES}" | sed 's/,/\n/g' | sed 's/[][]//g' | sed 's/"//g'
            echo "❌ Image not pushed to Docker Hub due to security concerns."
            exit 1
        fi
    fi
    
    echo "⏳ Still waiting for scan results... (${COUNT}/${MAX_TRIES})"
done

if [ ${COUNT} -ge ${MAX_TRIES} ]; then
    echo "❌ Timed out waiting for scan results."
    echo "❓ You can check the status manually in your GitHub repository."
    exit 1
fi