//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#pragma once

#include "model4cpp.h"
#include "sprite4cpp.h"
#include <memory>
#include <simd/vector_types.h>
#include <string>
#include <string_view>
#include <vector>

class CameraData;

enum class TextAlign3D
{
  LeftBottom = 0,
  CenterBottom,
  RightBottom,
};

//
class ApplicationContext
{

public:
  ApplicationContext()          = default;
  virtual ~ApplicationContext() = default;

  // info
  virtual float ContentScale() const = 0;

  // text
  virtual void Print(std::string_view msg, float x, float y)                 = 0;
  virtual void SetTextColor(float red, float green, float blue, float alpha) = 0;
  virtual void SetTextFont(std::string_view fontName)                        = 0;
  virtual void SetTextFontSize(float fontSize)                               = 0;
  virtual void SetTextFontColor(float red, float green, float blue, float alpha) = 0;

  // 2D
  virtual void DrawLine(simd_float2 from, simd_float2 to, simd_float4 color)                    = 0;
  virtual void DrawRect(simd_float2 from, simd_float2 to, simd_float4 color)                    = 0;
  virtual void DrawRoundRect(simd_float2 from, simd_float2 to, float radius,
                             simd_float4 color)                                                 = 0;
  virtual void FillRect(simd_float2 from, simd_float2 to, simd_float4 color)                    = 0;
  virtual void FillRoundRect(simd_float2 from, simd_float2 to, float radius,
                             simd_float4 color)                                                 = 0;
  virtual void DrawPolygon(simd_float2 pos, float rad, float rot, int sides, simd_float4 color) = 0;
  virtual void FillPolygon(simd_float2 pos, float rad, float rot, int sides, simd_float4 color) = 0;

  using SpritePtr                                   = std::shared_ptr<SpriteCpp>;
  virtual SpritePtr CreateSprite(std::string fname) = 0;
  virtual void      DrawSprite(SpritePtr spr)       = 0;

  // 3D
  virtual CameraData &GetCamera() = 0;

  virtual void SetLight3D(simd_float3 direction, float ambient, float diffuse) = 0;
  virtual void DrawLine3D(simd_float3 from, simd_float3 to, simd_float4 color) = 0;
  virtual void DrawTriangle3D(simd_float3 p0, simd_float3 p1, simd_float3 p2,
                              simd_float4 color)                               = 0;
  virtual void DrawPlane3D(simd_float3 p0, simd_float3 p1, simd_float3 p2, simd_float3 p3,
                           simd_float4 color)                                  = 0;
  virtual void DrawSphere3D(simd_float3 center, float radius, simd_float4 color,
                            int slices = 24, int stacks = 12)                  = 0;
  virtual void DrawBox3D(simd_float3 center, simd_float3 size, simd_float4 color) = 0;
  virtual void DrawBox3D(simd_float3 center, simd_float3 size, float rotationY,
                         simd_float4 color)                                      = 0;
  virtual void DrawBox3D(simd_float3 center, simd_float3 size, simd_float3 rotation,
                         simd_float4 color)                                      = 0;
  virtual void DrawCylinder3D(simd_float3 center, float radius, float height, simd_float4 color,
                              int segments = 24)                                 = 0;
  virtual void DrawCylinder3D(simd_float3 center, float radius, float height,
                              simd_float3 rotation, simd_float4 color,
                              int segments = 24)                                 = 0;
  virtual void DrawCone3D(simd_float3 center, float radius, float height, simd_float4 color,
                          int segments = 24)                                     = 0;
  virtual void DrawCone3D(simd_float3 center, float radius, float height, simd_float3 rotation,
                          simd_float4 color, int segments = 24)                  = 0;
  virtual void DrawCone3D(simd_float3 center, simd_float3 direction, float radius, float height,
                          simd_float4 color, int segments = 24)                  = 0;
  virtual void DrawText3D(std::string_view msg, simd_float3 position, float lineHeight,
                          simd_float4 color,
                          TextAlign3D align = TextAlign3D::LeftBottom)            = 0;
  virtual void DrawText3D(std::string_view msg, simd_float3 position, float lineHeight,
                          simd_float3 rotation, simd_float4 color,
                          TextAlign3D align = TextAlign3D::LeftBottom)            = 0;
  using ModelPtr                                  = std::shared_ptr<ModelCpp>;
  virtual ModelPtr LoadModel(std::string fname)   = 0;
  virtual void     DrawModel3D(ModelPtr model,
                               simd_float3 position,
                               simd_float3 rotation,
                               simd_float3 scale,
                               simd_float4 color = simd_float4{1.0f, 1.0f, 1.0f, 1.0f}) = 0;
};

//
class ApplicationLoop
{
public:
  ApplicationLoop()          = default;
  virtual ~ApplicationLoop() = default;

  // window title
  [[nodiscard]] virtual const char *GetApplicationName() const { return "Alloy3D"; };

  // start window size
  virtual bool InitialWindowSize(double &width, double &height, bool &border) { return true; }
  // to close window
  virtual void WillCloseWindow() {}
  // window clear color
  virtual void WindowClearColor(double &red, double &green, double &blue, double &alpha) {}
  // resize window
  virtual void ResizeWindow(double width, double height) {}
  // file drop
  virtual void DroppedFiles(const std::vector<std::string> &paths) {}

  // start after window initialization
  virtual void Start(ApplicationContext &ctx) {}
  // main update loop
  virtual void Update(ApplicationContext &ctx) = 0;
};

//
void LaunchApplication(std::shared_ptr<ApplicationLoop> apploop);

//
