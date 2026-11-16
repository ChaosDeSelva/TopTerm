#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
swift build -c release --disable-sandbox --product TopTerm
app_dir="$project_dir/build/TopTerm.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp .build/release/TopTerm "$app_dir/Contents/MacOS/TopTerm"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp Vendor/SwiftTerm/LICENSE "$app_dir/Contents/Resources/SwiftTerm-LICENSE.txt"
if [[ -f Resources/TopTerm.icns ]]; then
    cp Resources/TopTerm.icns "$app_dir/Contents/Resources/TopTerm.icns"
fi
codesign --force --sign - "$app_dir"
print -r -- "$app_dir"
