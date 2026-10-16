# Vendored libretro subset: only the INTERFACE target is needed. granite-util
# links granite-application-global-interface purely for its include directory
# (e.g. message_queue.hpp consumers). The granite-application-global and
# granite-application-global-init libraries link pruned targets
# (granite-threading, granite-event, granite-filesystem) and compile TUs that
# the libretro core does not build, so they are dropped.
add_library(granite-application-global-interface INTERFACE)
target_include_directories(granite-application-global-interface INTERFACE ${CMAKE_CURRENT_SOURCE_DIR})
