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

add_executable(alloy3d_instance_regression instance_regression.mm)
target_include_directories(alloy3d_instance_regression PRIVATE ../functions/internal)
target_link_libraries(alloy3d_instance_regression PRIVATE Alloy3D::application)
add_dependencies(alloy3d_instance_regression shaders)
add_test(NAME instance_regression COMMAND alloy3d_instance_regression
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib
  ${CMAKE_SOURCE_DIR}/assets/tests/rendering
  ${CMAKE_SOURCE_DIR}/assets/tests/animation/rig_25.glb)
set_tests_properties(instance_regression PROPERTIES
  ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)

add_executable(alloy3d_camera_regression camera_regression.mm)
target_include_directories(alloy3d_camera_regression PRIVATE ../functions/internal)
target_link_libraries(alloy3d_camera_regression PRIVATE Alloy3D::application)
add_dependencies(alloy3d_camera_regression shaders)
add_test(NAME camera_cpu COMMAND alloy3d_camera_regression --cpu)
add_test(NAME camera_gpu COMMAND alloy3d_camera_regression
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib
  ${CMAKE_SOURCE_DIR}/assets/tests/rendering
  ${CMAKE_SOURCE_DIR}/assets/tests/animation/rig_25.glb)
set_tests_properties(camera_gpu PROPERTIES ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)

add_executable(alloy3d_material_regression material_regression.mm)
target_include_directories(alloy3d_material_regression PRIVATE ../functions/internal)
target_link_libraries(alloy3d_material_regression PRIVATE Alloy3D::application)
add_dependencies(alloy3d_material_regression shaders)
add_test(NAME material_regression COMMAND alloy3d_material_regression
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib
  ${CMAKE_SOURCE_DIR}/assets/tests/materials)
set_tests_properties(material_regression PROPERTIES ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)

add_executable(alloy3d_shadow_regression shadow_regression.mm)
target_include_directories(alloy3d_shadow_regression PRIVATE ../functions/internal)
target_link_libraries(alloy3d_shadow_regression PRIVATE Alloy3D::application)
add_dependencies(alloy3d_shadow_regression shaders)
add_test(NAME shadow_regression COMMAND alloy3d_shadow_regression
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib
  ${CMAKE_SOURCE_DIR}/assets/tests/materials)
set_tests_properties(shadow_regression PROPERTIES ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)

add_executable(alloy3d_environment_regression environment_regression.mm)
target_include_directories(alloy3d_environment_regression PRIVATE ../functions/internal)
target_link_libraries(alloy3d_environment_regression PRIVATE Alloy3D::application)
add_dependencies(alloy3d_environment_regression shaders)
add_test(NAME environment_regression COMMAND alloy3d_environment_regression
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib
  ${CMAKE_SOURCE_DIR}/assets/tests/materials)
set_tests_properties(environment_regression PROPERTIES ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)

add_executable(alloy3d_environment_probe ../tools/environment_probe.mm)
target_include_directories(alloy3d_environment_probe PRIVATE ../functions/internal)
target_link_libraries(alloy3d_environment_probe PRIVATE Alloy3D::application)
add_dependencies(alloy3d_environment_probe shaders)

add_executable(alloy3d_shader_regression shader_regression.mm)
target_include_directories(alloy3d_shader_regression PRIVATE ../functions/internal)
target_link_libraries(alloy3d_shader_regression PRIVATE Alloy3D::application)
add_dependencies(alloy3d_shader_regression shaders)
add_test(NAME shader_regression COMMAND alloy3d_shader_regression
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib
  ${CMAKE_SOURCE_DIR}/assets/tests/materials)
set_tests_properties(shader_regression PROPERTIES ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)

foreach(SUITE material shadow)
  add_test(NAME shader_${SUITE} COMMAND alloy3d_${SUITE}_regression
    ${CMAKE_BINARY_DIR}/shaders/shaders.metallib
    ${CMAKE_SOURCE_DIR}/assets/tests/materials --custom-surface)
  set_tests_properties(shader_${SUITE} PROPERTIES ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)
endforeach()

add_executable(alloy3d_renderer_lifecycle MACOSX_BUNDLE renderer_lifecycle.mm)
target_include_directories(alloy3d_renderer_lifecycle PRIVATE ../application/src)
target_link_libraries(alloy3d_renderer_lifecycle PRIVATE Alloy3D::application)
add_dependencies(alloy3d_renderer_lifecycle shaders)
set_property(TARGET alloy3d_renderer_lifecycle APPEND PROPERTY LINK_DEPENDS
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib)
add_custom_command(TARGET alloy3d_renderer_lifecycle POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory
    $<TARGET_BUNDLE_DIR:alloy3d_renderer_lifecycle>/Contents/Resources/shaders
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    ${CMAKE_BINARY_DIR}/shaders/shaders.metallib
    $<TARGET_BUNDLE_DIR:alloy3d_renderer_lifecycle>/Contents/Resources/shaders/shaders.metallib)
foreach(FRAMES 0 1 3)
  add_test(NAME renderer_shutdown_${FRAMES} COMMAND alloy3d_renderer_lifecycle ${FRAMES})
  set_tests_properties(renderer_shutdown_${FRAMES} PROPERTIES
    ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77 TIMEOUT 30)
endforeach()
