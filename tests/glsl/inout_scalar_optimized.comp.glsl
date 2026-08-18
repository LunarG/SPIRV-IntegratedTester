// RUN: %glslang && %spirv_opt %spv -O -o %spv

// This shader is the same as inout_scalar.comp.glsl. In that test, one
// DebugDeclare over real memory describes the parameter of addOne, and
// another describes `v` in main.
//
// This test adds a general SPIR-V optimizer pass. The pass can move both
// variables out of memory and into SSA values. A DebugLocalVariable
// instruction must still describe each variable.
// CHECK: [[PARAM_V:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable
// CHECK: [[MAIN_V:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable

// After main loads `v`, the Value operand of DebugValue for `v` is the value
// that main loaded.
// CHECK: [[LOAD:%[0-9]+]] = OpLoad %float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[MAIN_V]] [[LOAD]]

// main calls addOne with the value of `v`. The Value operand of DebugValue
// for the parameter of addOne is this same value.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[PARAM_V]] [[LOAD]]

// Inside addOne, a real OpFAdd instruction adds one to the parameter. The
// Value operand of DebugValue for the parameter is this sum. addOne writes to
// its parameter one time only, so no earlier write exists for this value to
// supersede.
// CHECK: [[SUM:%[0-9]+]] = OpFAdd %float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[PARAM_V]] [[SUM]]

// After addOne returns, the Value operand of DebugValue for `v` in main is
// this same sum.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[MAIN_V]] [[SUM]]

#version 450
layout(set = 0, binding = 1, std430) buffer SSBO {
    float data;
};

void addOne(inout float v) {
    v = v + 1.0;
}

void main() {
    float v = data;
    addOne(v);
    data = v;
}
