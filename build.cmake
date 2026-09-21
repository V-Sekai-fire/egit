# SPDX-License-Identifier: Apache-2.0
#
# Configure and build in one command, so the build needs cmake and nothing
# else. elixir_make runs `make` on Unix and `nmake` on Windows by default and
# neither is present on every desk here, while cmake already has to be.
#
#   cmake -P build.cmake

set(SRC "${CMAKE_CURRENT_LIST_DIR}")
set(BLD "${SRC}/build")

if(DEFINED ENV{CMAKE_PREFIX_PATH})
  set(PREFIX "-DCMAKE_PREFIX_PATH=$ENV{CMAKE_PREFIX_PATH}")
endif()

# Ninja when it is there. Left to itself cmake picks the Visual Studio
# generator on Windows and ignores CC/CXX, which silently builds with a
# different compiler than the one the desk configured.
find_program(NINJA ninja)
if(NINJA)
  set(GEN -G Ninja)
endif()

execute_process(
  COMMAND ${CMAKE_COMMAND} -S "${SRC}" -B "${BLD}" ${GEN}
          -DCMAKE_BUILD_TYPE=Release ${PREFIX}
  RESULT_VARIABLE rc)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "configure failed")
endif()

execute_process(COMMAND ${CMAKE_COMMAND} --build "${BLD}" RESULT_VARIABLE rc)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "build failed")
endif()
