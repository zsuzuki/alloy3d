#
# Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
#
cmake_minimum_required(VERSION 3.21)

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin" AND NOT CMAKE_OSX_ARCHITECTURES)
  set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "macOS architectures to build" FORCE)
endif()

project(Alloy3D
  VERSION 0.1.0
  DESCRIPTION "Lightweight C++/Objective-C++ 3D rendering library for macOS Metal"
  LANGUAGES CXX OBJCXX
)

include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

option(ALLOY3D_BUILD_VIEWER "Build the bundled Alloy3D sample viewer app" ON)
option(ALLOY3D_INSTALL "Enable install rules for Alloy3D library targets and headers" ON)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 20)
set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT APPLE)
  message(FATAL_ERROR "Alloy3D is a macOS Metal library. Configure on macOS with Xcode or Command Line Tools installed.")
endif()

if(NOT CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64" AND NOT CMAKE_OSX_ARCHITECTURES MATCHES "(^|;)arm64($|;)")
  message(FATAL_ERROR "Alloy3D currently supports arm64 macOS builds only. Configure with -DCMAKE_OSX_ARCHITECTURES=arm64.")
endif()

find_program(XCRUN_EXECUTABLE xcrun REQUIRED)

execute_process(
  COMMAND "${XCRUN_EXECUTABLE}" -sdk macosx --show-sdk-path
  OUTPUT_VARIABLE MACOSX_SDK_PATH
  OUTPUT_STRIP_TRAILING_WHITESPACE
  RESULT_VARIABLE MACOSX_SDK_RESULT
  ERROR_VARIABLE MACOSX_SDK_ERROR
)
if(NOT MACOSX_SDK_RESULT EQUAL 0 OR NOT EXISTS "${MACOSX_SDK_PATH}")
  message(FATAL_ERROR "macOS SDK was not found via xcrun. Install/select Xcode or Command Line Tools.")
endif()

set(METAL_CHECK_DIR "${CMAKE_BINARY_DIR}/CMakeFiles/alloy3d-metal-check")
set(METAL_MODULE_CACHE_DIR "${CMAKE_BINARY_DIR}/CMakeFiles/MetalModuleCache")
file(MAKE_DIRECTORY "${METAL_CHECK_DIR}")
file(MAKE_DIRECTORY "${METAL_MODULE_CACHE_DIR}")
file(WRITE "${METAL_CHECK_DIR}/check.metal" "#include <metal_stdlib>\nusing namespace metal;\nkernel void alloy3d_check() {}\n")
execute_process(
  COMMAND "${XCRUN_EXECUTABLE}" -sdk macosx metal -fmodules-cache-path=${METAL_MODULE_CACHE_DIR} -o "${METAL_CHECK_DIR}/check.ir" -c "${METAL_CHECK_DIR}/check.metal"
  RESULT_VARIABLE METAL_CHECK_RESULT
  ERROR_VARIABLE METAL_CHECK_ERROR
  OUTPUT_QUIET
)
if(NOT METAL_CHECK_RESULT EQUAL 0)
  message(FATAL_ERROR "Metal shader compiler failed. Install/select a working Xcode Metal toolchain.\n${METAL_CHECK_ERROR}")
endif()
execute_process(
  COMMAND "${XCRUN_EXECUTABLE}" -sdk macosx metallib -o "${METAL_CHECK_DIR}/check.metallib" "${METAL_CHECK_DIR}/check.ir"
  RESULT_VARIABLE METALLIB_CHECK_RESULT
  ERROR_VARIABLE METALLIB_CHECK_ERROR
  OUTPUT_QUIET
)
if(NOT METALLIB_CHECK_RESULT EQUAL 0)
  message(FATAL_ERROR "Metal shader linker failed. Install/select a working Xcode Metal toolchain with metallib support.\n${METALLIB_CHECK_ERROR}")
endif()

find_library(METAL_FRAMEWORK Metal REQUIRED)
find_library(COCOA_FRAMEWORK Cocoa REQUIRED)
find_library(COREGRAPHICS_FRAMEWORK CoreGraphics REQUIRED)
find_library(METALKIT_FRAMEWORK MetalKit REQUIRED)
find_library(GAMECONTROLLER_FRAMEWORK GameController REQUIRED)
find_library(CORETEXT_FRAMEWORK CoreText REQUIRED)
find_library(COREIMAGE_FRAMEWORK CoreImage REQUIRED)
find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)

add_subdirectory(shaders)
add_subdirectory(application)
add_subdirectory(functions)

add_library(Alloy3D::functions ALIAS functions)
add_library(Alloy3D::application ALIAS application)

target_link_libraries(functions
  PUBLIC
    ${METAL_FRAMEWORK}
    ${METALKIT_FRAMEWORK}
    ${GAMECONTROLLER_FRAMEWORK}
    ${CORETEXT_FRAMEWORK}
    ${COREIMAGE_FRAMEWORK}
    ${COREGRAPHICS_FRAMEWORK}
    ${FOUNDATION_FRAMEWORK}
)
target_link_libraries(application
  PUBLIC
    functions
    ${COCOA_FRAMEWORK}
    ${METALKIT_FRAMEWORK}
    ${FOUNDATION_FRAMEWORK}
)

if(ALLOY3D_BUILD_VIEWER)
  set(ALLOY3D_VIEWER_SOURCES
    samples/viewer/main.cpp
  )

  add_executable(alloy3d_viewer MACOSX_BUNDLE ${ALLOY3D_VIEWER_SOURCES})
  target_link_libraries(alloy3d_viewer
    PRIVATE
      Alloy3D::application
  )

  set(SHADERS_LIB ${CMAKE_BINARY_DIR}/shaders/shaders.metallib)
  set(ALLOY3D_SAMPLE_RESOURCES
    assets/samples/models/animated_bouncer.glb
    assets/samples/models/sample_cube.glb
    assets/samples/models/sample_mdl.glb
  )

  set_target_properties(alloy3d_viewer PROPERTIES
    MACOSX_BUNDLE TRUE
    MACOSX_FRAMEWORK_IDENTIFIER org.suzukiz.alloy3d.viewer
  )

  foreach(RFILES ${ALLOY3D_SAMPLE_RESOURCES})
    file(RELATIVE_PATH fname "${CMAKE_CURRENT_SOURCE_DIR}/assets/samples" "${CMAKE_CURRENT_SOURCE_DIR}/${RFILES}")
    get_filename_component(fdir ${fname} DIRECTORY)
    set_source_files_properties(${RFILES} PROPERTIES MACOSX_PACKAGE_LOCATION "Resources/${fdir}")
    add_custom_command(TARGET alloy3d_viewer POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${CMAKE_CURRENT_SOURCE_DIR}/${RFILES}
        $<TARGET_FILE_DIR:alloy3d_viewer>/../Resources/${fname}
      COMMENT "COPY: ${RFILES}"
    )
  endforeach()

  add_dependencies(alloy3d_viewer shaders)
  add_custom_command(TARGET alloy3d_viewer POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory
      $<TARGET_FILE_DIR:alloy3d_viewer>/../Resources/shaders
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      ${SHADERS_LIB}
      $<TARGET_FILE_DIR:alloy3d_viewer>/../Resources/shaders/shaders.metallib
    COMMENT "COPY: Shader Library"
  )
endif()

if(ALLOY3D_INSTALL)
  install(TARGETS functions application
    EXPORT Alloy3DTargets
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
  )
  install(DIRECTORY include/ DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})
  install(FILES ${CMAKE_BINARY_DIR}/shaders/shaders.metallib
    DESTINATION ${CMAKE_INSTALL_DATADIR}/alloy3d/shaders
    OPTIONAL
  )

  write_basic_package_version_file(
    ${CMAKE_CURRENT_BINARY_DIR}/Alloy3DConfigVersion.cmake
    VERSION ${PROJECT_VERSION}
    COMPATIBILITY SameMajorVersion
  )
  configure_package_config_file(
    cmake/Alloy3DConfig.cmake.in
    ${CMAKE_CURRENT_BINARY_DIR}/Alloy3DConfig.cmake
    INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/Alloy3D
  )
  install(EXPORT Alloy3DTargets
    NAMESPACE Alloy3D::
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/Alloy3D
  )
  install(FILES
    ${CMAKE_CURRENT_BINARY_DIR}/Alloy3DConfig.cmake
    ${CMAKE_CURRENT_BINARY_DIR}/Alloy3DConfigVersion.cmake
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/Alloy3D
  )
endif()
