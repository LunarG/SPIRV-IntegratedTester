// RUN: %slangc

// A DebugLocalVariable instruction must describe the local variable `v`.
// CHECK: [[UNDEF:%[0-9]+]] = OpUndef %v4float
// CHECK: %v = OpExtInst {{.*}} DebugLocalVariable

// The NonSemantic.Shader.DebugInfo.100 contract for DebugValue is one rule.
// The Value operand must be the real value of the local variable, at the point
// in the program where the DebugValue instruction appears.
//
// After the shader loads `v`, the contract holds. The Value operand of
// DebugValue is the value that the shader loaded.
// CHECK: [[LOAD:%[0-9]+]] = OpLoad %v4float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %v [[LOAD]]

// After the write `v.zyx = v.xyz * 2.0`, a real value for `v` exists. The
// shader builds it from the multiplied x, y, and z values.
// CHECK: [[MUL:%[0-9]+]] = OpVectorTimesScalar %v3float
// CHECK: [[EXTRACT:%[0-9]+]] = OpCompositeExtract %float [[MUL]]
// CHECK: {{%[0-9]+}} = OpCompositeInsert %v4float [[EXTRACT]]

// At this point, the DebugValue contract does not hold. The Value operand of
// DebugValue for `v` is a bare OpUndef value, and not the real value above. A
// debugger shows `v` as fully undefined at this line, even though three of its
// four components are known.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %v [[UNDEF]]

// The write `v.w = v.x + v.y` obeys the contract. The Value operand of
// DebugValue is the sum, with an Indexes operand that selects component 3.
// CHECK: [[SUM:%[0-9]+]] = OpFAdd %float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %v [[SUM]] {{%[0-9]+}} %int_3

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
