add_executable(alloy3d_render_probe ../tools/render_probe.mm)
target_include_directories(alloy3d_render_probe PRIVATE ../functions/internal)
target_link_libraries(alloy3d_render_probe PRIVATE Alloy3D::application)
add_dependencies(alloy3d_render_probe shaders)
add_test(NAME render_stress COMMAND alloy3d_render_probe
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib
  ${CMAKE_SOURCE_DIR}/assets/samples/models/animated_bouncer.glb --stress)
set_tests_properties(render_stress PROPERTIES
  ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)

add_executable(alloy3d_buffer_regression buffer_regression.mm)
target_include_directories(alloy3d_buffer_regression PRIVATE ../functions/internal)
target_link_libraries(alloy3d_buffer_regression PRIVATE Alloy3D::application)
add_dependencies(alloy3d_buffer_regression shaders)
add_test(NAME buffer_regression COMMAND alloy3d_buffer_regression
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib
  ${CMAKE_SOURCE_DIR}/assets/samples/models/animated_bouncer.glb)
set_tests_properties(buffer_regression PROPERTIES
  ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)

add_executable(alloy3d_animation_regression animation_regression.mm)
target_include_directories(alloy3d_animation_regression PRIVATE ../functions/internal)
target_link_libraries(alloy3d_animation_regression PRIVATE Alloy3D::application)
add_dependencies(alloy3d_animation_regression shaders)
add_test(NAME animation_regression COMMAND alloy3d_animation_regression
  ${CMAKE_CURRENT_SOURCE_DIR}/../assets/tests/animation
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib --require-no-alloc)
set_tests_properties(animation_regression PROPERTIES
  ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)

add_executable(alloy3d_memory_regression memory_regression.mm)
target_include_directories(alloy3d_memory_regression PRIVATE ../functions/internal)
target_link_libraries(alloy3d_memory_regression PRIVATE Alloy3D::application)
add_dependencies(alloy3d_memory_regression shaders)
add_test(NAME memory_regression COMMAND alloy3d_memory_regression
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib)
set_tests_properties(memory_regression PROPERTIES
  ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)
