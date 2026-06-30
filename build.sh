#!/bin/bash
set -e

# Create the app bundle structure
mkdir -p HourlyChime.app/Contents/MacOS
mkdir -p HourlyChime.app/Contents/Resources

# Copy Info.plist into bundle
cp HourlyChime/Info.plist HourlyChime.app/Contents/Info.plist

# Compile the Swift source
swiftc HourlyChime/AppDelegate.swift \
  -o HourlyChime.app/Contents/MacOS/HourlyChime \
  -framework AppKit \
  -framework Foundation \
  -framework ServiceManagement \
  -target arm64-apple-macosx13.0  # Note: produces Apple Silicon (arm64) binary only. Use Xcode for universal builds.

echo "Build complete. Run with: open HourlyChime.app"
