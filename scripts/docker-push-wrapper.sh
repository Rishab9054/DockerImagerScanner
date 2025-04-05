#!/bin/bash

set -e

image_name="$1"

if [[ -z "$image_name" ]]; then
  echo "Usage: docker-push push <image_name>"
  exit 1
fi

# Save Docker image
tmp_dir=$(mktemp -d)
tar_file="$tmp_dir/image.tar"
docker save -o "$tar_file" "$image_name"
echo "✅ Saved image as $tar_file"

# Upload image as artifact using GitHub CLI
echo "📦 Uploading image artifact..."
gh artifact upload docker-image "$tar_file" --repo <your_username>/<repo_name>

# Trigger workflow
echo "🚀 Triggering GitHub workflow..."
gh workflow run docker-security-scan.yml \
  --repo <your_username>/<repo_name> \
  --ref main \
  -f image_name="$image_name"

echo "✅ Workflow triggered. Monitor it on GitHub Actions."
