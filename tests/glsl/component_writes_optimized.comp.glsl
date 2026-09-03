// RUN: %glslang && %spirv_opt %spv -O -o %spv

// glslang compiles `v` as a normal local variable. Both writes to `v` use
// plain numbers, so a general SPIR-V optimizer pass can compute the final
// value of `v` at compile time.
//
// This test asserts what the debug information for `v` names after each of the
// two writes. The two results are different, and both are correct.
// CHECK: [[REAL:%[0-9]+]] = OpConstantComposite %v2float %float_5 %float_6
// CHECK: [[UNDEF:%[0-9]+]] = OpUndef %v2float
// CHECK: [[v:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable

// After the write `v.x = 5.0`, the value of `v` is `{x=5, y=undefined}`. No
// single value in the module is equal to this. The optimizer cannot build one,
// because a NonSemantic.Shader.DebugInfo.100 instruction must never add a
// semantic instruction to the module. So the Value operand of DebugValue is a
// bare OpUndef value. A debugger reports that `v` has no value at this line.
// The cause is the contract for a non-semantic extension, and not an optimizer
// defect.
//
// The test `component_write_optimized.comp.glsl` has one write only. There the
// same partial value is semantically live, so the debug information names it.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[v]] [[UNDEF]]

// After the write `v.y = 6.0`, the Value operand of DebugValue for `v` is the
// final value. The same value reaches the output buffer.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[v]] [[REAL]]
// CHECK: OpStore {{%[0-9]+}} [[REAL]]

#version 450
layout(set = 0, binding = 1, std430) buffer SSBO { vec2 data; };
void main() {
    vec2 v;
    v.x = 5.0;
    v.y = 6.0;
    data = v;
}
