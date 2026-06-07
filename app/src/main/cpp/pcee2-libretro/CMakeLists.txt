add_library(pcee2-libretro SHARED)

set_target_properties(pcee2-libretro PROPERTIES
	OUTPUT_NAME "pcee2_libretro"
	PREFIX ""
	RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
	LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

if (PACKAGE_MODE)
	install(TARGETS pcee2-libretro DESTINATION ${CMAKE_INSTALL_LIBDIR})
else()
	install(TARGETS pcee2-libretro DESTINATION ${CMAKE_SOURCE_DIR}/bin)
endif()

target_sources(pcee2-libretro PRIVATE
	Libretro.cpp
	libretro.h
)

target_include_directories(pcee2-libretro PRIVATE
	"${CMAKE_CURRENT_SOURCE_DIR}"
	"${CMAKE_BINARY_DIR}/common/include"
	"${CMAKE_SOURCE_DIR}/pcsx2"
)

target_link_libraries(pcee2-libretro PRIVATE
	PCSX2_FLAGS
	PCSX2
)

# undefined symbols in a core otherwise surface only when the frontend loads
# it ("symbol lookup error" at runtime) - fail the link instead
if(UNIX AND NOT APPLE)
	target_link_options(pcee2-libretro PRIVATE "-Wl,--no-undefined")
endif()
