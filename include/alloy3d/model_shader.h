#pragma once
#include <memory>

namespace alloy3d
{
// Immutable, context-owned compiled model surface shader. Keep and reuse the handle.
class ModelShader
{
protected:
  ModelShader() = default;

public:
  virtual ~ModelShader()                      = default;
  ModelShader(const ModelShader &)            = delete;
  ModelShader &operator=(const ModelShader &) = delete;
};
using ModelShaderPtr = std::shared_ptr<ModelShader>;
} // namespace alloy3d
