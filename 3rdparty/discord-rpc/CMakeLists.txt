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
	# Neither of the two register implementations can be built here: the macOS
	# one needs AppKit and the Linux one calls system(), and iOS and tvOS have
	# neither. Nor is there a Discord client on either to register with. The
	# connection half is plain unix sockets and builds anywhere, so only the
	# register side is stubbed.
	target_sources(discord-rpc PRIVATE
		src/connection_unix.cpp
		src/discord_register_stub.cpp
	)
elseif(UNIX)
	target_sources(discord-rpc PRIVATE
		src/connection_unix.cpp
		src/discord_register_linux.cpp
	)
endif()
