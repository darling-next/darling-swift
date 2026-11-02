// Runtime reexport facade, not a replacement for the SDK's source module.
// build_module emits the genuine Swift force-load marker for the selected
// module name and links LC_REEXPORT_DYLIB to its complete real provider.
// Do not redeclare Darwin types here: all facades must share their metadata.
import Swift
