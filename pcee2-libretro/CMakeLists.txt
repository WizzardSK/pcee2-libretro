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
	libretro_core_options.h
	libretro_core_options_intl.h
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
# The DirectX shader compiler is not part of Windows: the standalone ships
# dxcompiler.dll beside its executable, a core is one file. Linked the usual
# way, the core did not load at all where that DLL is missing (error 126),
# whichever renderer was chosen. Delay-loaded, it is looked for only when the
# Direct3D 12 renderer compiles a shader, which checks for it first (D3D.cpp).
if(MSVC)
	target_link_options(pcee2_libretro PRIVATE "/DELAYLOAD:dxcompiler.dll")
	target_link_libraries(pcee2_libretro PRIVATE delayimp.lib)
endif()

if(UNIX AND NOT APPLE)
	target_link_options(pcee2_libretro PRIVATE
		"-Wl,--no-undefined"
		"-Wl,-Bsymbolic"
		"-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/libretro.map")
	set_property(TARGET pcee2_libretro APPEND PROPERTY
		LINK_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/libretro.map")
endif()

# The Metal GS device's shaders. A standalone PCSX2 ships them as .metallib
# files in its app bundle; a core has no bundle of its own - NSBundle's main
# bundle is the frontend's, whose default.metallib holds the frontend's
# shaders - so build one library (Metal 2.3, the macOS 11 deployment target)
# and link it into the core, where GSMTLDeviceInfo.mm reads it back from the
# __DATA,__pcsx2_mtllib section. The core stays a single file.
if(APPLE AND NOT APPLE_EMBEDDED)
	get_property(PCSX2_SOURCE_DIR GLOBAL PROPERTY PCSX2_SOURCE_DIR)
	get_property(PCSX2_METAL_SHADERS GLOBAL PROPERTY PCSX2_METAL_SHADERS)
	set(core_metal_air)
	foreach(shader IN LISTS PCSX2_METAL_SHADERS)
		set(air ${CMAKE_CURRENT_BINARY_DIR}/metal/${shader}.air)
		get_filename_component(air_dir ${air} DIRECTORY)
		add_custom_command(OUTPUT ${air}
			COMMAND ${CMAKE_COMMAND} -E make_directory ${air_dir}
			COMMAND xcrun metal -ffast-math -std=macos-metal2.3 -target air64-apple-macos11.0
				-o ${air} -c ${PCSX2_SOURCE_DIR}/${shader}
			DEPENDS ${PCSX2_SOURCE_DIR}/${shader}
				${PCSX2_SOURCE_DIR}/GS/Renderers/Metal/GSMTLSharedHeader.h
				${PCSX2_SOURCE_DIR}/GS/Renderers/Metal/GSMTLShaderCommon.h
		)
		list(APPEND core_metal_air ${air})
	endforeach()
	set(core_metallib ${CMAKE_CURRENT_BINARY_DIR}/pcsx2.metallib)
	add_custom_command(OUTPUT ${core_metallib}
		COMMAND xcrun metallib -o ${core_metallib} ${core_metal_air}
		DEPENDS ${core_metal_air}
	)
	add_custom_target(pcee2_libretro_metallib DEPENDS ${core_metallib})
	add_dependencies(pcee2_libretro pcee2_libretro_metallib)
	target_link_options(pcee2_libretro PRIVATE
		"LINKER:-sectcreate,__DATA,__pcsx2_mtllib,${core_metallib}")
	set_property(TARGET pcee2_libretro APPEND PROPERTY LINK_DEPENDS ${core_metallib})
endif()
