// RUN: %slangc -O0

// This shader is the same as swizzle.slang. This test turns off all of the
// slang optimizations. A DebugLocalVariable instruction must still describe
// the local variable `v`.
// CHECK: %v_0 = OpExtInst {{.*}} DebugLocalVariable

// After the shader loads `v`, the Value operand of DebugValue is the value
// that the shader loaded.
// CHECK: [[LOAD:%[0-9]+]] = OpLoad %v4float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %v_0 [[LOAD]]

// After the write `v.zyx = v.xyz * 2.0`, the shader reloads `v` from real
// memory. The Value operand of DebugValue for `v` is this reloaded value. It
// holds the new x, y, and z values, together with the unchanged w value.
// CHECK: {{%[0-9]+}} = OpVectorTimesScalar %v3float
// CHECK: [[RELOAD:%[0-9]+]] = OpLoad %v4float %v
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %v_0 [[RELOAD]]

// The write `v.w = v.x + v.y` behaves the same way. The Value operand of
// DebugValue is the sum, with an Indexes operand that selects component 3.
// CHECK: [[SUM:%[0-9]+]] = OpFAdd %float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %v_0 [[SUM]] {{%[0-9]+}} %int_3

struct SSBO {
    float4 data;
};

[[vk::binding(1, 0)]]
RWStructuredBuffer<SSBO> ssbo;

[shader("compute")]
[numthreads(1, 1, 1)]
void main() {
    float4 v = ssbo[0].data;
    v.zyx = v.xyz * 2.0;
    v.w = v.x + v.y;
    ssbo[0].data = v.wzyx;
}
