// RUN: %glslang && %spirv_opt %spv -O -o %spv

// This test is the contrast case for component_writes_optimized.comp.glsl.
// This shader writes one component of `v` only. No statement in this program
// assigns `v.y`, so the value of `v.y` is undefined. The cause is the source
// program, and not an optimizer defect.
// CHECK: [[UNDEFINED_Y:%[0-9]+]] = OpUndef %v2float
// CHECK: [[v:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable

// A general SPIR-V optimizer pass builds the final value of `v` from two
// components. The first is the known component x, which the shader sets to
// 5.0. The second is the undefined component y.
//
// The Value operand of DebugValue for `v` is this combined value, and not the
// bare undefined value alone. The same value reaches the output buffer.
// CHECK: [[REAL:%[0-9]+]] = OpCompositeInsert %v2float %float_5 [[UNDEFINED_Y]] 0
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[v]] [[REAL]]
// CHECK: OpStore {{%[0-9]+}} [[REAL]]

#version 450
layout(set = 0, binding = 1, std430) buffer SSBO { vec2 data; };
void main() {
    vec2 v;
    v.x = 5.0;
    data = v;
}
