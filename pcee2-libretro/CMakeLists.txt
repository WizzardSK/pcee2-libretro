add_library(pcee2_libretro SHARED)

set_target_properties(pcee2_libretro PROPERTIES
	OUTPUT_NAME "pcee2_libretro"
	PREFIX ""
	RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
	LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

if (PACKAGE_MODE)
	install(TARGETS pcee2_libretro DESTINATION ${CMAKE_INSTALL_LIBDIR})
else()
	install(TARGETS pcee2_libretro DESTINATION ${CMAKE_SOURCE_DIR}/bin)
endif()

# The libretro buildbot expects the .so directly in the build dir root (it does
# `mv $BUILD_DIR/pcee2_libretro.so ...`), while the GitHub/standalone packaging
# uses bin/. Copy it to the build root too so both layouts work.
add_custom_command(TARGET pcee2_libretro POST_BUILD
	COMMAND ${CMAKE_COMMAND} -E copy
		$<TARGET_FILE:pcee2_libretro> ${CMAKE_BINARY_DIR}/pcee2_libretro.so)

target_sources(pcee2_libretro PRIVATE
	Libretro.cpp
	LibretroVFS.cpp
	LibretroVFS.h
	libretro.h
)

target_include_directories(pcee2_libretro PRIVATE
	"${CMAKE_CURRENT_SOURCE_DIR}"
	"${CMAKE_BINARY_DIR}/common/include"
	"${CMAKE_SOURCE_DIR}/pcsx2"
)

target_link_libraries(pcee2_libretro PRIVATE
	PCSX2_FLAGS
	PCSX2
)

# undefined symbols in a core otherwise surface only when the frontend loads
# it ("symbol lookup error" at runtime) - fail the link instead.
#
# -Bsymbolic and the version script keep the core self-contained inside the
# frontend's process: the core binds its own definitions rather than whatever
# the frontend already has under the same name, and exports nothing but the
# libretro entry points. See libretro.map for what went wrong without them.
if(UNIX AND NOT APPLE)
	target_link_options(pcee2_libretro PRIVATE
		"-Wl,--no-undefined"
		"-Wl,-Bsymbolic"
		"-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/libretro.map")
	set_property(TARGET pcee2_libretro APPEND PROPERTY
		LINK_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/libretro.map")
endif()
