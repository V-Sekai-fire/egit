# SPDX-License-Identifier: Apache-2.0

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

# AUTO: a libgit2 under a system prefix is used, anything else is vendored. A
# system library is on the machine that runs the artefact; one from a package
# environment is on the machine that built it.
set(EGIT_LIBGIT2 "AUTO" CACHE STRING "AUTO, SYSTEM or VENDORED")
set(EGIT_LIBGIT2_TAG "v1.9.7" CACHE STRING "libgit2 tag to vendor")

set(EGIT_SYSTEM_PREFIXES /usr /usr/local /opt/homebrew)

if(NOT EGIT_LIBGIT2 STREQUAL "VENDORED")
  find_path(SYS_GIT2_INCLUDE git2.h PATHS /usr/include /usr/local/include
            /opt/homebrew/include NO_DEFAULT_PATH)
  find_library(SYS_GIT2_LIB NAMES git2 PATHS /usr/lib /usr/lib64 /lib
               /usr/lib/x86_64-linux-gnu /usr/lib/aarch64-linux-gnu
               /usr/local/lib /opt/homebrew/lib NO_DEFAULT_PATH)
endif()

if(SYS_GIT2_INCLUDE AND SYS_GIT2_LIB)
  set(EGIT_LIBGIT2_SOURCE "system")
  set(GIT2_LIBRARY "${SYS_GIT2_LIB}")
  set(GIT2_INCLUDE_DIR "${SYS_GIT2_INCLUDE}")
elseif(EGIT_LIBGIT2 STREQUAL "SYSTEM")
  message(FATAL_ERROR "EGIT_LIBGIT2=SYSTEM but no libgit2 under ${EGIT_SYSTEM_PREFIXES}")
else()
  set(EGIT_LIBGIT2_SOURCE "vendored")
  include(FetchContent)
  set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
  set(BUILD_TESTS       OFF CACHE BOOL "" FORCE)
  set(BUILD_CLI         OFF CACHE BOOL "" FORCE)
  set(BUILD_EXAMPLES    OFF CACHE BOOL "" FORCE)
  set(BUILD_FUZZERS     OFF CACHE BOOL "" FORCE)
  set(USE_SSH           "exec" CACHE STRING "" FORCE)
  set(USE_BUNDLED_ZLIB  ON  CACHE STRING "" FORCE)
  set(REGEX_BACKEND     "builtin" CACHE STRING "" FORCE)

  FetchContent_Declare(libgit2
    GIT_REPOSITORY https://github.com/libgit2/libgit2.git
    GIT_TAG        ${EGIT_LIBGIT2_TAG}
    GIT_SHALLOW    TRUE)
  FetchContent_MakeAvailable(libgit2)

  set(GIT2_LIBRARY libgit2package)
  set(GIT2_INCLUDE_DIR "${libgit2_SOURCE_DIR}/include")
endif()

# Which libgit2 this artefact carries. A system library is on the machine that
# runs it; one from a package environment is on the machine that built it.
if(EGIT_LIBGIT2_SOURCE STREQUAL "system")
  set(EGIT_LIBGIT2_DETAIL "${GIT2_LIBRARY}")
else()
  set(EGIT_LIBGIT2_DETAIL "${EGIT_LIBGIT2_TAG} static")
endif()
message(STATUS "libgit2: ${EGIT_LIBGIT2_SOURCE} ${EGIT_LIBGIT2_DETAIL}")

file(GLOB EGIT_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/c_src/*.cpp")
add_library(git MODULE ${EGIT_SOURCES})

target_include_directories(git PRIVATE
  "${ERTS_INCLUDE}" "${EI_INCLUDE}" "${GIT2_INCLUDE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/c_src")

# Detected, not assumed: the compiler may predate <format>.
include(CheckCXXSourceCompiles)
set(CMAKE_REQUIRED_FLAGS "-std=c++20")
check_cxx_source_compiles("#include <format>
int main(){return (int)std::format(\"{}\",1).size();}" HAVE_STD_FORMAT)
check_cxx_source_compiles("#include <source_location>
int main(){return (int)std::source_location::current().line();}" HAVE_STD_SRCLOC)
unset(CMAKE_REQUIRED_FLAGS)

if(HAVE_STD_FORMAT)
  target_compile_definitions(git PRIVATE HAVE_FORMAT)
else()
  if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/c_src/fmt/include")
    execute_process(COMMAND git submodule update --init --recursive
                    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" RESULT_VARIABLE rc)
    if(NOT rc EQUAL 0 OR NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/c_src/fmt/include")
      message(FATAL_ERROR "no <format> and no c_src/fmt; use a C++20 compiler or fetch the submodule")
    endif()
  endif()
  target_compile_definitions(git PRIVATE FMT_HEADER_ONLY)
  target_include_directories(git PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/c_src/fmt/include")
endif()
if(HAVE_STD_SRCLOC)
  target_compile_definitions(git PRIVATE HAVE_SRCLOC)
endif()

# No -lei: nothing references ei_*, and its MSVC import library breaks lld.
target_link_libraries(git PRIVATE "${GIT2_LIBRARY}")

if(MSVC)
  target_compile_options(git PRIVATE /EHsc /W3 /utf-8)
else()
  target_compile_options(git PRIVATE -Wall -finline-functions)
endif()

if(MINGW)
  target_link_options(git PRIVATE -static -static-libgcc -static-libstdc++)
endif()

if(APPLE)
  target_link_options(git PRIVATE -undefined dynamic_lookup)
endif()

# elixir_make archives $MIX_APP_PATH/priv. Mix symlinks that to ./priv on Unix
if(DEFINED ENV{MIX_APP_PATH})
  set(EGIT_PRIV "$ENV{MIX_APP_PATH}/priv")
else()
  set(EGIT_PRIV "${CMAKE_CURRENT_SOURCE_DIR}/priv")
endif()
file(MAKE_DIRECTORY "${EGIT_PRIV}")
message(STATUS "priv: ${EGIT_PRIV}")

# Provenance beside the artefact: which libgit2 it carries and what built it,
# so a downloaded NIF can be traced without unpacking it.
file(WRITE "${EGIT_PRIV}/egit.sigs"
"# Generated by CMakeLists.txt; do not edit.
libgit2 ${EGIT_LIBGIT2_SOURCE} ${EGIT_LIBGIT2_DETAIL}
compiler ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}
system ${CMAKE_SYSTEM_NAME} ${CMAKE_SYSTEM_PROCESSOR}
")

set_target_properties(git PROPERTIES
  PREFIX ""
  LIBRARY_OUTPUT_DIRECTORY "${EGIT_PRIV}"
  RUNTIME_OUTPUT_DIRECTORY "${EGIT_PRIV}")

foreach(cfg IN ITEMS DEBUG RELEASE RELWITHDEBINFO MINSIZEREL)
  set_target_properties(git PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY_${cfg} "${EGIT_PRIV}"
    RUNTIME_OUTPUT_DIRECTORY_${cfg} "${EGIT_PRIV}")
endforeach()
