#!/bin/bash

VERSION="1.1.4"

# Commit changes
git add .
git commit -m "Release v${VERSION}"
git push origin main

# Create tag and release
git tag "v${VERSION}"
git push origin "v${VERSION}"

# Get SHA256
curl -sL "https://github.com/XIOTS/xiops/archive/refs/tags/v${VERSION}.tar.gz" -o "xiops-${VERSION}.tar.gz"
SHA256=$(shasum -a 256 "xiops-${VERSION}.tar.gz" | awk '{print $1}')
echo "SHA256: $SHA256"

# Update formula (you'll need to do this manually or script it)
echo "Update Formula/xiops.rb with:"
echo "  version: ${VERSION}"
echo "  sha256: ${SHA256}"

# Clean up
rm "xiops-${VERSION}.tar.gz"