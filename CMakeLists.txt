# SPDX-License-Identifier: Apache-2.0
#
# Builds the egit NIF on Windows, Linux and macOS with one description.
#
# The hand-written c_src/Makefile reaches for pkg-config and g++ and writes a
# .so. On Windows none of the three hold: pkg-config is absent, no g++ is on
# PATH, and Erlang loads priv/git.dll. CMake already knows the difference
# between the toolchains, so the branching lives here rather than in shell.
#
# The Erlang paths are asked of the running erl rather than guessed, which is
# what the Makefile did too and is the one part of it worth keeping.

cmake_minimum_required(VERSION 3.20)
project(egit_nif CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

function(erl_eval out expr)
  execute_process(
    COMMAND erl -noshell -noinput -eval "${expr}"
    OUTPUT_VARIABLE result OUTPUT_STRIP_TRAILING_WHITESPACE
    RESULT_VARIABLE code)
  if(NOT code EQUAL 0)
    message(FATAL_ERROR "erl is not on PATH; egit needs the Erlang headers")
  endif()
  set(${out} "${result}" PARENT_SCOPE)
endfunction()

erl_eval(ERTS_INCLUDE
  "io:format(\"~ts/erts-~ts/include\", [code:root_dir(), erlang:system_info(version)]), halt(0).")
erl_eval(EI_INCLUDE "io:format(\"~ts\", [code:lib_dir(erl_interface, include)]), halt(0).")
erl_eval(EI_LIB "io:format(\"~ts\", [code:lib_dir(erl_interface, lib)]), halt(0).")

find_path(GIT2_INCLUDE_DIR git2.h)

# On Windows the packaged libgit2 is built with MSVC, and its import library
# carries /DEFAULTLIB:LIBCMT and /DEFAULTLIB:OLDNAMES directives that lld in
# MinGW mode cannot satisfy - it looks for libLIBCMT.a and libOLDNAMES.a and
# stops. libgit2 is a C library, so linking the DLL itself skips the
# directives and keeps the ABI, which is the same thing the import library
# would have given us.
if(MINGW)
  find_file(GIT2_LIBRARY NAMES git2.dll libgit2.dll PATH_SUFFIXES bin)
endif()
if(NOT GIT2_LIBRARY)
  find_library(GIT2_LIBRARY NAMES git2 libgit2)
endif()

if(NOT GIT2_INCLUDE_DIR OR NOT GIT2_LIBRARY)
  message(FATAL_ERROR "libgit2 not found; set CMAKE_PREFIX_PATH at it")
endif()
message(STATUS "libgit2: ${GIT2_LIBRARY}")

file(GLOB EGIT_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/c_src/*.cpp")
add_library(git MODULE ${EGIT_SOURCES})

target_include_directories(git PRIVATE
  "${ERTS_INCLUDE}" "${EI_INCLUDE}" "${GIT2_INCLUDE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/c_src")

# std::format and std::source_location rather than the vendored fmt. Every
# compiler this targets has both at C++20, and the bundled fmt exists for the
# older ones the Makefile still supported.
target_compile_definitions(git PRIVATE HAVE_FORMAT HAVE_SRCLOC)

# erl_interface is not linked. The NIF uses only erl_nif.h, whose enif_*
# entry points the emulator resolves at load time, and on Windows ei.lib is an
# MSVC import library whose /DEFAULTLIB:LIBCMT and /DEFAULTLIB:OLDNAMES
# directives send lld looking for libLIBCMT.a. The Makefile passed -lei for a
# symbol nothing references.
target_link_libraries(git PRIVATE "${GIT2_LIBRARY}")

if(MSVC)
  target_compile_options(git PRIVATE /EHsc /W3 /utf-8)
else()
  target_compile_options(git PRIVATE -Wall -finline-functions)
endif()

if(MINGW)
  # The shipped artefact must not need llvm-mingw's libc++.dll and
  # libunwind.dll beside it: a NIF is loaded by the emulator, which does not
  # add the compiler's bin directory to the DLL search path, so a dynamic
  # link there loads on the desk that built it and nowhere else.
  target_link_options(git PRIVATE -static -static-libgcc -static-libstdc++)
endif()

if(APPLE)
  # A NIF resolves enif_* out of the running emulator at load time.
  target_link_options(git PRIVATE -flat_namespace -undefined suppress)
endif()

# Under Mix the library belongs in the built application's priv, not the source
# tree's. elixir_make archives what is in $MIX_APP_PATH/priv, and on Unix Mix
# symlinks that to ./priv so writing to either works, while on Windows it is a
# real and separate directory - so a build that only wrote ./priv produced an
# archive of nothing, and reported a checksum for it.
if(DEFINED ENV{MIX_APP_PATH})
  set(EGIT_PRIV "$ENV{MIX_APP_PATH}/priv")
else()
  set(EGIT_PRIV "${CMAKE_CURRENT_SOURCE_DIR}/priv")
endif()
file(MAKE_DIRECTORY "${EGIT_PRIV}")
message(STATUS "priv: ${EGIT_PRIV}")

# Erlang loads priv/git.<ext>, so no lib prefix and no version suffix.
set_target_properties(git PROPERTIES
  PREFIX ""
  LIBRARY_OUTPUT_DIRECTORY "${EGIT_PRIV}"
  RUNTIME_OUTPUT_DIRECTORY "${EGIT_PRIV}")

foreach(cfg IN ITEMS DEBUG RELEASE RELWITHDEBINFO MINSIZEREL)
  set_target_properties(git PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY_${cfg} "${EGIT_PRIV}"
    RUNTIME_OUTPUT_DIRECTORY_${cfg} "${EGIT_PRIV}")
endforeach()
