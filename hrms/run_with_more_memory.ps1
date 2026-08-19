# Run Flutter with more Dart VM heap to avoid "Out of memory" / "kernel_snapshot_program failed"
# Use this if: flutter run fails with allocation.cc: error: Out of memory

$env:DART_VM_OPTIONS = "--old_gen_heap_size=4096"
flutter run @args
