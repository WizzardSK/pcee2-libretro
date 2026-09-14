set(SRCS
	include/discord_register.h
	include/discord_rpc.h
	src/backoff.h
	src/connection.h
	src/discord_rpc.cpp
	src/msg_queue.h
	src/rpc_connection.cpp
	src/rpc_connection.h
	src/serialization.cpp
	src/serialization.h
)

add_library(discord-rpc ${SRCS})
target_include_directories(discord-rpc PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(discord-rpc rapidjson)

# Needed for macOS compile.
set_property(TARGET discord-rpc PROPERTY CXX_STANDARD 17)
set_property(TARGET discord-rpc PROPERTY CXX_STANDARD_REQUIRED ON)

if(WIN32)
	target_sources(discord-rpc PRIVATE
		src/connection_win.cpp
		src/discord_register_win.cpp
	)
elseif(APPLE AND NOT APPLE_EMBEDDED)
	target_sources(discord-rpc PRIVATE
		src/connection_unix.cpp
		src/discord_register_osx.m
	)
elseif(APPLE_EMBEDDED)
	# discord_register_osx.m registers the discord:// handler through
	# NSWorkspace, and AppKit does not exist on iOS or tvOS - nor does a
	# Discord client to register with. The POSIX variant keeps the same two
	# symbols defined and writes a .desktop file nothing will ever read, which
	# is the honest shape of "not available here": the connection half is plain
	# unix sockets and builds anywhere.
	target_sources(discord-rpc PRIVATE
		src/connection_unix.cpp
		src/discord_register_linux.cpp
	)
elseif(UNIX)
	target_sources(discord-rpc PRIVATE
		src/connection_unix.cpp
		src/discord_register_linux.cpp
	)
endif()
