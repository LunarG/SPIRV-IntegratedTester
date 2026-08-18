// RUN: %glslang && %spirv_opt %spv -O -o %spv

// This shader is the same as inout_multi.comp.glsl. In that test, one
// DebugDeclare over real memory describes each of the four variables: the two
// parameters of addOneToBoth, and `a` and `b` in main.
//
// This test adds a general SPIR-V optimizer pass. The pass can move all four
// variables out of memory and into SSA values. A DebugLocalVariable
// instruction must still describe each variable.
// CHECK: [[PARAM_A:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable
// CHECK: [[PARAM_B:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable
// CHECK: [[MAIN_A:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable
// CHECK: [[MAIN_B:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable

// After main loads `a` and `b`, the Value operand of DebugValue for each
// variable is the value that main loaded for that variable. The two variables
// do not exchange values.
// CHECK: [[LOAD_A:%[0-9]+]] = OpLoad %v4float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[MAIN_A]] [[LOAD_A]]
// CHECK: [[LOAD_B:%[0-9]+]] = OpLoad %v4float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[MAIN_B]] [[LOAD_B]]

// main calls addOneToBoth with the values of `a` and `b`. The Value operand
// of DebugValue for each parameter is the value of the matching argument.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[PARAM_A]] [[LOAD_A]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[PARAM_B]] [[LOAD_B]]

// Inside addOneToBoth, a real OpFAdd instruction adds one to each parameter.
// The Value operand of DebugValue for each parameter is its own sum.
// addOneToBoth writes to each parameter one time only, so no earlier write
// exists for either value to supersede.
// CHECK: [[SUM_A:%[0-9]+]] = OpFAdd %v4float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[PARAM_A]] [[SUM_A]]
// CHECK: [[SUM_B:%[0-9]+]] = OpFAdd %v4float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[PARAM_B]] [[SUM_B]]

// After addOneToBoth returns, the Value operand of DebugValue for `a` and for
// `b` in main is the same sum as in addOneToBoth.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[MAIN_A]] [[SUM_A]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[MAIN_B]] [[SUM_B]]

#version 450
layout(set = 0, binding = 1, std430) buffer SSBO {
    vec4 dataA;
    vec4 dataB;
};

void addOneToBoth(inout vec4 a, inout vec4 b) {
    a = a + vec4(1.0, 1.0, 1.0, 1.0);
    b = b + vec4(1.0, 1.0, 1.0, 1.0);
}

void main() {
    vec4 a = dataA;
    vec4 b = dataB;
    addOneToBoth(a, b);
    dataA = a;
    dataB = b;
}
