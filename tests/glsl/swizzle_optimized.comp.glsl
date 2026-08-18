// RUN: %glslang && %spirv_opt %spv -O -o %spv

// This shader is the same as swizzle.comp.glsl. In that test, glslang keeps
// `v` in real memory, so the debug information for `v` needs no later change.
//
// This test adds a general SPIR-V optimizer pass. The pass can move `v` out of
// memory, into a new value for each write. If the pass does this, it must also
// update the debug information for `v` to match.
// CHECK: [[UNDEF:%[0-9]+]] = OpUndef %v4float
// CHECK: [[v:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable

// After the shader loads `v`, the Value operand of DebugValue for `v` is the
// value that the shader loaded.
// CHECK: [[LOAD:%[0-9]+]] = OpLoad %v4float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[v]] [[LOAD]]

// After the write `v.zyx = v.xyz * 2.0`, a real value for `v` exists. The
// shader builds it from the multiplied x, y, and z values.
// CHECK: [[MUL:%[0-9]+]] = OpVectorTimesScalar %v3float
// CHECK: {{%[0-9]+}} = OpCompositeExtract %float [[MUL]]

// At this point, the Value operand of DebugValue for `v` is a bare OpUndef
// value. It is not the real value above. A debugger shows `v` as fully
// undefined at this line, even though three of its four components are
// known.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[v]] [[UNDEF]]

// After the write `v.w = v.x + v.y`, the Value operand of DebugValue for `v`
// is a real value again. It is the full vector, with the sum in place of the
// old w value.
// CHECK: [[SUM:%[0-9]+]] = OpFAdd %float
// CHECK: [[REAL:%[0-9]+]] = OpCompositeConstruct %v4float {{.*}} [[SUM]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[v]] [[REAL]]

#version 450
layout(set = 0, binding = 1, std430) buffer SSBO {
    vec4 data;
};

void main() {
    vec4 v = data;
    v.zyx = v.xyz * 2.0;
    v.w = v.x + v.y;
    data = v.wzyx;
}
