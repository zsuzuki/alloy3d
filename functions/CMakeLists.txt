#
# Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
#
cmake_minimum_required(VERSION 3.21)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

project(functions)

set(SOURCES
  src/camera.cpp
  src/sprite.mm
  src/draw2d.mm
  src/draw3d.mm
  src/font_render.mm
  src/memory_cache.mm
  src/game_pad.mm
  src/keyboard.mm
  src/model.mm
  src/texture.mm
)

set(SHADER_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../shaders")
set(MODEL_SHADER_PREFIX "")
foreach(PART shader_def.h shadow.h model_surface.h)
  file(READ "${SHADER_SOURCE_DIR}/${PART}" PART_SOURCE)
  string(APPEND MODEL_SHADER_PREFIX "\n${PART_SOURCE}")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${SHADER_SOURCE_DIR}/${PART}")
endforeach()
file(READ "${SHADER_SOURCE_DIR}/simple3d.metal" MODEL_SHADER_BODY)
string(REGEX REPLACE "#include \"[^\"]+\"" "" MODEL_SHADER_BODY "${MODEL_SHADER_BODY}")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${SHADER_SOURCE_DIR}/simple3d.metal")
configure_file(src/model_shader_source.h.in generated/model_shader_source.h @ONLY)

add_library(${PROJECT_NAME} ${SOURCES})
target_include_directories(${PROJECT_NAME}
  PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/../include>
    $<INSTALL_INTERFACE:include>
  PRIVATE
    ${CMAKE_CURRENT_BINARY_DIR}/generated
    ${CMAKE_CURRENT_SOURCE_DIR}/internal
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/cgltf
    ${CMAKE_CURRENT_SOURCE_DIR}/../shaders
)
set_target_properties(${PROJECT_NAME} PROPERTIES
  EXPORT_NAME functions
  OUTPUT_NAME alloy3d_functions
)
