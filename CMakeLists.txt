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

option(EGIT_VENDOR_LIBGIT2 "Build libgit2 from source and link it statically" ON)
set(EGIT_LIBGIT2_TAG "v1.9.7" CACHE STRING "libgit2 tag to vendor")

if(EGIT_VENDOR_LIBGIT2)
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
  message(STATUS "libgit2: vendored ${EGIT_LIBGIT2_TAG}, static")
else()
  find_path(GIT2_INCLUDE_DIR git2.h)
  if(MINGW)
    find_file(GIT2_LIBRARY NAMES git2.dll libgit2.dll PATH_SUFFIXES bin)
  endif()
  if(NOT GIT2_LIBRARY)
    find_library(GIT2_LIBRARY NAMES git2 libgit2)
  endif()
  if(NOT GIT2_INCLUDE_DIR OR NOT GIT2_LIBRARY)
    message(FATAL_ERROR "libgit2 not found; set CMAKE_PREFIX_PATH at it")
  endif()
  message(STATUS "libgit2: packaged ${GIT2_LIBRARY}")
endif()

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

set_target_properties(git PROPERTIES
  PREFIX ""
  LIBRARY_OUTPUT_DIRECTORY "${EGIT_PRIV}"
  RUNTIME_OUTPUT_DIRECTORY "${EGIT_PRIV}")

foreach(cfg IN ITEMS DEBUG RELEASE RELWITHDEBINFO MINSIZEREL)
  set_target_properties(git PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY_${cfg} "${EGIT_PRIV}"
    RUNTIME_OUTPUT_DIRECTORY_${cfg} "${EGIT_PRIV}")
endforeach()
