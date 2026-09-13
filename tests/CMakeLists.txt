add_executable(alloy3d_material_shader_regression material_shader_regression.mm)
target_include_directories(alloy3d_material_shader_regression PRIVATE ../functions/internal)
target_link_libraries(alloy3d_material_shader_regression PRIVATE Alloy3D::application)
add_dependencies(alloy3d_material_shader_regression shaders)
add_test(NAME material_shader_regression COMMAND alloy3d_material_shader_regression
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib ${CMAKE_SOURCE_DIR}/assets/tests/materials)
set_tests_properties(material_shader_regression PROPERTIES ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)
add_executable(alloy3d_alpha_coverage_regression alpha_coverage_regression.mm)
target_include_directories(alloy3d_alpha_coverage_regression PRIVATE ../functions/internal)
target_link_libraries(alloy3d_alpha_coverage_regression PRIVATE Alloy3D::application)
add_dependencies(alloy3d_alpha_coverage_regression shaders)
add_test(NAME alpha_coverage_regression COMMAND alloy3d_alpha_coverage_regression
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib ${CMAKE_SOURCE_DIR}/assets/tests/materials)
set_tests_properties(alpha_coverage_regression PROPERTIES ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)
add_executable(alloy3d_wind_regression wind_regression.mm)
target_include_directories(alloy3d_wind_regression PRIVATE ../functions/internal)
target_link_libraries(alloy3d_wind_regression PRIVATE Alloy3D::application)
add_dependencies(alloy3d_wind_regression shaders)
add_test(NAME wind_regression COMMAND alloy3d_wind_regression
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib ${CMAKE_SOURCE_DIR}/assets/tests/materials)
set_tests_properties(wind_regression PROPERTIES ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)
add_executable(alloy3d_lod_regression lod_regression.mm)
target_include_directories(alloy3d_lod_regression PRIVATE ../functions/internal)
target_link_libraries(alloy3d_lod_regression PRIVATE Alloy3D::application)
add_dependencies(alloy3d_lod_regression shaders)
add_test(NAME lod_regression COMMAND alloy3d_lod_regression
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib ${CMAKE_SOURCE_DIR}/assets/tests/materials)
set_tests_properties(lod_regression PROPERTIES ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)
add_executable(alloy3d_visibility_regression visibility_regression.mm)
target_include_directories(alloy3d_visibility_regression PRIVATE ../functions/internal)
target_link_libraries(alloy3d_visibility_regression PRIVATE Alloy3D::application)
add_dependencies(alloy3d_visibility_regression shaders)
add_test(NAME visibility_regression COMMAND alloy3d_visibility_regression
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib ${CMAKE_SOURCE_DIR}/assets/tests/materials)
set_tests_properties(visibility_regression PROPERTIES ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)
add_executable(alloy3d_forest_probe ../tools/forest_probe.mm)
add_executable(alloy3d_transparent_batch_regression transparent_batch_regression.mm)
target_include_directories(alloy3d_transparent_batch_regression PRIVATE ../functions/internal)
target_link_libraries(alloy3d_transparent_batch_regression PRIVATE Alloy3D::application)
add_dependencies(alloy3d_transparent_batch_regression shaders)
add_test(NAME transparent_batch_regression COMMAND alloy3d_transparent_batch_regression
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib ${CMAKE_SOURCE_DIR}/assets/tests/materials)
set_tests_properties(transparent_batch_regression PROPERTIES ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)
add_executable(alloy3d_height_fog_regression height_fog_regression.mm)
target_include_directories(alloy3d_height_fog_regression PRIVATE ../functions/internal)
target_link_libraries(alloy3d_height_fog_regression PRIVATE Alloy3D::application)
add_dependencies(alloy3d_height_fog_regression shaders)
add_test(NAME height_fog_regression COMMAND alloy3d_height_fog_regression
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib ${CMAKE_SOURCE_DIR}/assets/tests/materials)
set_tests_properties(height_fog_regression PROPERTIES ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)
add_executable(alloy3d_surface_detail_regression surface_detail_regression.mm)
target_include_directories(alloy3d_surface_detail_regression PRIVATE ../functions/internal)
target_link_libraries(alloy3d_surface_detail_regression PRIVATE Alloy3D::application)
add_dependencies(alloy3d_surface_detail_regression shaders)
add_test(NAME surface_detail_regression COMMAND alloy3d_surface_detail_regression
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib ${CMAKE_SOURCE_DIR}/assets/tests/surface)
set_tests_properties(surface_detail_regression PROPERTIES ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)
add_executable(alloy3d_normal_mapping_regression normal_mapping_regression.mm)
target_include_directories(alloy3d_normal_mapping_regression PRIVATE ../functions/internal)
target_link_libraries(alloy3d_normal_mapping_regression PRIVATE Alloy3D::application)
add_dependencies(alloy3d_normal_mapping_regression shaders)
add_test(NAME normal_mapping_regression COMMAND alloy3d_normal_mapping_regression
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib ${CMAKE_SOURCE_DIR}/assets/tests/normals)
set_tests_properties(normal_mapping_regression PROPERTIES ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)
add_executable(alloy3d_msaa_regression msaa_regression.mm)
target_include_directories(alloy3d_msaa_regression PRIVATE ../functions/internal)
target_link_libraries(alloy3d_msaa_regression PRIVATE Alloy3D::application)
add_dependencies(alloy3d_msaa_regression shaders)
add_test(NAME msaa_regression COMMAND alloy3d_msaa_regression
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib ${CMAKE_SOURCE_DIR}/assets/tests/materials)
set_tests_properties(msaa_regression PROPERTIES ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)
add_executable(alloy3d_forest_billboard_baker ../tools/bake_forest_billboards.mm)
target_include_directories(alloy3d_forest_billboard_baker PRIVATE ../functions/internal)
target_link_libraries(alloy3d_forest_billboard_baker PRIVATE Alloy3D::application)
add_dependencies(alloy3d_forest_billboard_baker shaders)
target_include_directories(alloy3d_forest_probe PRIVATE ../functions/internal)
target_link_libraries(alloy3d_forest_probe PRIVATE Alloy3D::application)
add_dependencies(alloy3d_forest_probe shaders)
add_test(NAME forest_scene COMMAND alloy3d_forest_probe
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib
  ${CMAKE_SOURCE_DIR}/assets/samples/forest
  ${CMAKE_BINARY_DIR}/forest-preview)
set_tests_properties(forest_scene PROPERTIES ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77 TIMEOUT 90)

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

add_executable(alloy3d_highlight_probe ../tools/highlight_probe.mm)
target_include_directories(alloy3d_highlight_probe PRIVATE ../functions/internal)
target_link_libraries(alloy3d_highlight_probe PRIVATE Alloy3D::application)
add_dependencies(alloy3d_highlight_probe shaders)

add_executable(alloy3d_highlight_regression highlight_regression.mm)
target_include_directories(alloy3d_highlight_regression PRIVATE ../functions/internal)
target_link_libraries(alloy3d_highlight_regression PRIVATE Alloy3D::application)
add_dependencies(alloy3d_highlight_regression shaders)
add_test(NAME highlight_regression COMMAND alloy3d_highlight_regression
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib
  ${CMAKE_SOURCE_DIR}/assets/tests/materials)
set_tests_properties(highlight_regression PROPERTIES ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)

add_executable(alloy3d_mipmap_regression mipmap_regression.mm)
target_include_directories(alloy3d_mipmap_regression PRIVATE ../functions/internal)
target_link_libraries(alloy3d_mipmap_regression PRIVATE Alloy3D::application)
add_dependencies(alloy3d_mipmap_regression shaders)
add_test(NAME mipmap_regression COMMAND alloy3d_mipmap_regression
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib
  ${CMAKE_SOURCE_DIR}/assets/tests/mipmaps)
set_tests_properties(mipmap_regression PROPERTIES ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)

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

add_executable(alloy3d_texture_transform_regression texture_transform_regression.mm)
target_include_directories(alloy3d_texture_transform_regression PRIVATE ../functions/internal)
target_link_libraries(alloy3d_texture_transform_regression PRIVATE Alloy3D::application)
add_dependencies(alloy3d_texture_transform_regression shaders)
add_test(NAME texture_transform_regression COMMAND alloy3d_texture_transform_regression
  ${CMAKE_BINARY_DIR}/shaders/shaders.metallib
  ${CMAKE_SOURCE_DIR}/assets/tests/materials)
set_tests_properties(texture_transform_regression PROPERTIES ENVIRONMENT "MTL_DEBUG_LAYER=1" SKIP_RETURN_CODE 77)
