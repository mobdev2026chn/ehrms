# Build the release APK on a low-memory (7GB) box.
#
# WHY THIS SCRIPT EXISTS:
# `flutter build apk --release` crashes on this machine with:
#   IconTreeShakerException: ConstFinder failure: zone.cc: Out of memory
# The icon tree-shaker spawns a heavy Dart "ConstFinder" process. With Gradle
# also resident, total memory exceeds the 7GB box and one of them OOM-crashes.
# Giving the Dart VM a bigger heap (--old_gen_heap_size) just moves the OOM to
# the Gradle JVM ("Gradle build daemon disappeared unexpectedly").
#
# The only reliable fix here is to skip the tree-shaker with
# --no-tree-shake-icons. Cost: the full icon font ships (a few hundred KB) so
# the APK is marginally larger. That is the accepted trade-off on this box.
#
# Usage:
#   ./build_release_apk.ps1            # release APK
#   ./build_release_apk.ps1 --split-per-abi   # or pass any extra flutter flags

flutter build apk --release --no-tree-shake-icons @args

if ($LASTEXITCODE -eq 0) {
    $apk = "build\app\outputs\flutter-apk\app-release.apk"
    if (Test-Path $apk) {
        $sizeMB = [math]::Round((Get-Item $apk).Length / 1MB, 1)
        Write-Host ""
        Write-Host "BUILD OK -> $apk ($sizeMB MB)" -ForegroundColor Green
    }
} else {
    Write-Host ""
    Write-Host "BUILD FAILED (exit $LASTEXITCODE)" -ForegroundColor Red
}
