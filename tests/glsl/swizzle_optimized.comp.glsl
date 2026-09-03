// RUN: %glslang && %spirv_opt %spv -O -o %spv
// XFAIL: SPIRV-Tools#6718, DebugValue references OpUndef after spirv-opt

// This shader is the same as swizzle.comp.glsl. In that test, glslang keeps
// `v` in real memory, so the debug information for `v` needs no later change.
//
// This test adds a general SPIR-V optimizer pass. The pass can move `v` out of
// memory, into a new value for each write. If the pass does this, it must also
// update the debug information for `v` to match.
//
// This test is expected to fail today. Every component of `v` holds a defined
// value at every point in this shader. So a correct module contains no
// undefined 4-component vector, and the guard below asserts that.
//
// The optimizer emits one today. It attaches that undefined value to `v` after
// the write `v.zyx = v.xyz * 2.0`. See
// https://github.com/KhronosGroup/SPIRV-Tools/issues/6718.
//
// The guard names no replacement value, because more than one correct fix
// exists. A fix can describe each written component with the Indexes operand of
// DebugValue. A fix can also move the instruction. The guard accepts all of
// them, because it asserts only that the undefined value is gone.

// Assert that no undefined 4-component vector exists. This guard must stay
// first. Its search region ends at the next match, so a later position cannot
// reach the module scope where spirv-opt declares the value.
//
// Do not write this pattern as plain text. The compiler puts the shader source
// into the module, so plain text matches this comment and not an instruction.
// CHECK-NOT: {{%[0-9]+ = OpUndef %v4float}}
// CHECK: [[v:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable

// After the shader loads `v`, the Value operand of DebugValue for `v` is the
// value that the shader loaded.
// CHECK: [[LOAD:%[0-9]+]] = OpLoad %v4float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[v]] [[LOAD]]

// After the write `v.zyx = v.xyz * 2.0`, a real value for `v` exists. The
// shader builds it from the multiplied x, y, and z values.
// CHECK: [[MUL:%[0-9]+]] = OpVectorTimesScalar %v3float
// CHECK: {{%[0-9]+}} = OpCompositeExtract %float [[MUL]]

// At this point the optimizer attaches an undefined value to `v`. A debugger
// shows `v` as fully undefined at this line, even though three of its four
// components are known. The guard at the top of this test asserts that the
// undefined value does not exist.

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
