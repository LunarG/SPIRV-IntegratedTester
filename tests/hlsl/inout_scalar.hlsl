// RUN: %dxc -T cs_6_0

// A DebugLocalVariable instruction must describe the parameter `v` of addOne,
// and another must describe `v` in main. This test uses a plain float for `v`.
// The result does not depend on the vector type that the other inout test
// uses.
// CHECK: [[PARAM_V:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable
// CHECK: [[MAIN_V:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable

// After main loads `v`, the Value operand of DebugValue for `v` is the value
// that main loaded.
// CHECK: [[LOAD:%[0-9]+]] = OpLoad %float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[MAIN_V]] [[LOAD]]

// A real OpFAdd instruction adds one to `v`. The Value operand of DebugValue
// for the parameter of addOne is this sum.
// CHECK: [[SUM:%[0-9]+]] = OpFAdd %float [[LOAD]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[PARAM_V]] [[SUM]]

// After addOne returns, the Value operand of DebugValue for `v` in main is
// this same sum.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[MAIN_V]] [[SUM]]

struct SSBO {
    float data;
};

[[vk::binding(1, 0)]]
RWStructuredBuffer<SSBO> ssbo;

void addOne(inout float v) {
    v = v + 1.0;
}

[numthreads(1, 1, 1)]
void main() {
    float v = ssbo[0].data;
    addOne(v);
    ssbo[0].data = v;
}
