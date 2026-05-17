#
# Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
#
cmake_minimum_required(VERSION 3.21)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

project(application)

include_directories(include)

set(SOURCES
  src/app_delegate.mm
  src/renderer.mm
)

add_library(${PROJECT_NAME} ${SOURCES})
target_include_directories(${PROJECT_NAME} PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(${PROJECT_NAME} PRIVATE functions)
