#
# Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
#
cmake_minimum_required(VERSION 3.21)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

project(application)

set(SOURCES
  src/app_delegate.mm
  src/renderer.mm
)

add_library(${PROJECT_NAME} ${SOURCES})
target_include_directories(${PROJECT_NAME}
  PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/../include>
    $<INSTALL_INTERFACE:include>
  PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../functions/internal
)
target_link_libraries(${PROJECT_NAME} PUBLIC functions)
set_target_properties(${PROJECT_NAME} PROPERTIES
  EXPORT_NAME application
  OUTPUT_NAME alloy3d_application
)
