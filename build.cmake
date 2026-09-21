# SPDX-License-Identifier: Apache-2.0

set(SRC "${CMAKE_CURRENT_LIST_DIR}")
set(BLD "${SRC}/build")

if(DEFINED ENV{CMAKE_PREFIX_PATH})
  set(PREFIX "-DCMAKE_PREFIX_PATH=$ENV{CMAKE_PREFIX_PATH}")
endif()

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
