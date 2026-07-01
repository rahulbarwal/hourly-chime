#!/bin/bash
set -e

# Create the app bundle structure
mkdir -p HourlyChime.app/Contents/MacOS
mkdir -p HourlyChime.app/Contents/Resources

# Copy Info.plist into bundle
cp HourlyChime/Info.plist HourlyChime.app/Contents/Info.plist

# swiftc does not wire up the AppDelegate when @main calls NSApplicationMain
# without a nib file. We strip @main and supply a main.swift that explicitly
# sets NSApplication.shared.delegate so applicationDidFinishLaunching fires.
TMPDIR_BUILD=$(mktemp -d)
trap "rm -rf '$TMPDIR_BUILD'" EXIT

# Strip @main from the source so it can coexist with our main.swift entry point
sed 's/@main//' HourlyChime/AppDelegate.swift > "$TMPDIR_BUILD/AppDelegate.swift"

cat > "$TMPDIR_BUILD/main.swift" << 'SWIFT_EOF'
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
SWIFT_EOF

# Compile the Swift source
swiftc "$TMPDIR_BUILD/AppDelegate.swift" "$TMPDIR_BUILD/main.swift" \
  -o HourlyChime.app/Contents/MacOS/HourlyChime \
  -framework AppKit \
  -framework Foundation \
  -framework ServiceManagement \
  -target arm64-apple-macosx13.0  # Note: produces Apple Silicon (arm64) binary only. Use Xcode for universal builds.

echo "Build complete. Run with: open HourlyChime.app"
