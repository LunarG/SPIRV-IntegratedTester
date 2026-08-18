// RUN: %slangc -O0

// This shader is the same as inout_scalar.slang. This test turns off all of
// the slang optimizations. A DebugLocalVariable instruction must describe `v`
// in main, and another must describe the parameter `v` of addOne.
// CHECK: %v_0 = OpExtInst {{.*}} DebugLocalVariable
// CHECK: %v_2 = OpExtInst {{.*}} DebugLocalVariable

// After main loads `v`, the Value operand of DebugValue for `v` is the value
// that main loaded.
// CHECK: [[LOAD:%[0-9]+]] = OpLoad %float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %v_0 [[LOAD]]

// After addOne returns, main reloads `v` from real memory. The Value operand
// of DebugValue for `v` is this reloaded value.
// CHECK: [[RELOAD:%[0-9]+]] = OpLoad %float %v
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %v_0 [[RELOAD]]

// CHECK: %v_1 = OpFunctionParameter {{.*}}

// Inside addOne, the Value operand of DebugValue for the parameter is the real
// argument value that main passed in.
// CHECK: [[PARAM:%[0-9]+]] = OpLoad %float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %v_2 [[PARAM]]

// A real OpFAdd instruction adds one to the parameter of addOne. The Value
// operand of DebugValue for the parameter is this sum.
// CHECK: [[SUM:%[0-9]+]] = OpFAdd %float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %v_2 [[SUM]]

struct SSBO {
    float data;
};

[[vk::binding(1, 0)]]
RWStructuredBuffer<SSBO> ssbo;

void addOne(inout float v) {
    v = v + 1.0;
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main() {
    float v = ssbo[0].data;
    addOne(v);
    ssbo[0].data = v;
}
