# Vendored libretro subset: only application/global is needed (it defines
# granite-application-global-interface, the sole application-tree target linked
# by granite-util). The full granite-application library and the events/input/
# platforms subdirectories link pruned targets (granite-event, granite-input,
# granite-threading, granite-filesystem, ...) and are not part of the libretro
# core link closure, so they are dropped.
add_subdirectory(global)
