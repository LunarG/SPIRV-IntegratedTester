// RUN: %slangc
// XFAIL: SPIRV-Tools#6718, DebugValue references OpUndef after spirv-opt

// This test is expected to fail today. The guard below asserts that no
// DebugValue for `v` names an undefined value. The optimizer breaks that
// assertion after the write `v.zyx = v.xyz * 2.0`. See
// https://github.com/KhronosGroup/SPIRV-Tools/issues/6718.
//
// The guard names no replacement value, because more than one correct fix
// exists. A fix can name the composite that the shader builds. A fix can also
// describe each written component with the Indexes operand of DebugValue. The
// guard accepts all of them, because it asserts only that the undefined value
// is gone.
//
// This module holds two undefined 4-component vectors. Only one of them is a
// defect. The other is the start value for the composite that the shader
// builds, and the shader overwrites that component before the store. So this
// test cannot assert that no undefined vector exists. It asserts the narrower
// rule that no DebugValue names one.

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

// At this point the DebugValue contract must hold. The Value operand must not
// be an undefined value, because three of the four components of `v` are
// known. The optimizer names an undefined value today, so this guard fails.
//
// Keep this guard between the two anchors above and below it. The search
// region of a CHECK-NOT ends at the next match.
// CHECK-NOT: DebugValue %v [[UNDEF]]

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
