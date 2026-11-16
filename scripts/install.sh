#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> [1/4] Generating Xcode project with XcodeGen..."
cd "$PROJECT_DIR"
xcodegen generate

echo "==> [2/4] Building Release binary with xcodebuild..."
SIGN_ARGS=()
if [ -n "${SIQI_SIGN_IDENTITY:-}" ]; then
    SIGN_ARGS+=("CODE_SIGN_IDENTITY=$SIQI_SIGN_IDENTITY")
fi
if [ -n "${SIQI_DEVELOPMENT_TEAM:-}" ]; then
    SIGN_ARGS+=("DEVELOPMENT_TEAM=$SIQI_DEVELOPMENT_TEAM")
fi

xcodebuild -project siqi.xcodeproj -scheme siqi -configuration Release -destination 'platform=macOS' "${SIGN_ARGS[@]}" build > /tmp/siqi_build.log 2>&1 || {
    echo "❌ Build failed! Log output:"
    tail -n 40 /tmp/siqi_build.log
    exit 1
}

# Locate built app (newest wins: stale DerivedData dirs may also hold a build)
BUILT_APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/siqi-*/Build/Products/Release/siqi.app 2>/dev/null | head -n 1)

if [ -z "$BUILT_APP" ] || [ ! -d "$BUILT_APP" ]; then
    echo "❌ Error: Could not find built siqi.app in DerivedData!"
    exit 1
fi

echo "==> [3/4] Installing siqi.app to /Applications..."
if pgrep -x "siqi" > /dev/null 2>&1; then
    echo "    Stopping running siqi instance..."
    pkill -x "siqi" || true
    sleep 0.5
fi

rm -rf /Applications/siqi.app
cp -R "$BUILT_APP" /Applications/siqi.app

# xcodebuild registers its DerivedData output with LaunchServices, so Spotlight
# shows a second "siqi" next to the installed one. Drop that registration.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister
"$LSREGISTER" -u "$BUILT_APP" 2>/dev/null || true

# Do NOT re-sign here: xcodebuild already signed with SIQI_SIGN_IDENTITY (or ad-hoc default),
# and re-signing changes the CDHash, invalidating granted TCC permissions on each install.
echo "==> [4/4] Verifying signature and architecture..."
codesign -vvv /Applications/siqi.app 2>&1
codesign -d -r- /Applications/siqi.app 2>&1
ARCHS=$(lipo -archs /Applications/siqi.app/Contents/MacOS/siqi)
if [[ "$ARCHS" != *arm64* ]] || [[ "$ARCHS" != *x86_64* ]]; then
    echo "❌ Error: /Applications/siqi.app is not Universal (arm64 + x86_64): $ARCHS"
    exit 1
fi

echo ""
echo "🎉 siqi successfully built, signed, and installed to /Applications/siqi.app!"
