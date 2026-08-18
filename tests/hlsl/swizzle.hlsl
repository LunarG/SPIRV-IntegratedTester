// RUN: %dxc -T cs_6_0

// A DebugLocalVariable instruction must describe the local variable `v`.
// CHECK: [[v:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable

// After the shader loads `v`, the Value operand of DebugValue is the value
// that the shader loaded.
// CHECK: [[LOAD:%[0-9]+]] = OpLoad %v4float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[v]] [[LOAD]]

// After the write `v.zyx = v.xyz * 2.0`, the Value operand of DebugValue for
// `v` is the updated vector. It holds the new x, y, and z values, together
// with the unchanged w value.
// CHECK: [[XYZ:%[0-9]+]] = OpVectorShuffle %v3float [[LOAD]] [[LOAD]] 0 1 2
// CHECK: [[MUL:%[0-9]+]] = OpVectorTimesScalar %v3float [[XYZ]]
// CHECK: [[BLEND:%[0-9]+]] = OpVectorShuffle %v4float [[LOAD]] [[MUL]] 6 5 4 3
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[v]] [[BLEND]]

// The write `v.w = v.x + v.y` behaves the same way. The Value operand of
// DebugValue is the updated vector, with the sum in place of the old w
// value.
// CHECK: [[SUM:%[0-9]+]] = OpFAdd %float
// CHECK: [[INSERTED:%[0-9]+]] = OpCompositeInsert %v4float [[SUM]] [[BLEND]] 3
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[v]] [[INSERTED]]

struct SSBO {
    float4 data;
};

[[vk::binding(1, 0)]]
RWStructuredBuffer<SSBO> ssbo;

[numthreads(1, 1, 1)]
void main() {
    float4 v = ssbo[0].data;
    v.zyx = v.xyz * 2.0;
    v.w = v.x + v.y;
    ssbo[0].data = v.wzyx;
}
