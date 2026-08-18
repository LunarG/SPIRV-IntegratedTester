// RUN: %slangc

// A DebugLocalVariable instruction must describe `v` in main, and another must
// describe the parameter `v` of addOne.
// CHECK: [[UNDEF:%[0-9]+]] = OpUndef %v4float
// CHECK: %v = OpExtInst {{.*}} DebugLocalVariable
// CHECK: %v_0 = OpExtInst {{.*}} DebugLocalVariable

// After main loads `v`, the Value operand of DebugValue for `v` is the value
// that main loaded.
// CHECK: [[LOAD:%[0-9]+]] = OpLoad %v4float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %v [[LOAD]]

// main calls addOne with the value of `v`. The Value operand of DebugValue for
// the parameter of addOne (also named `v`) is a bare OpUndef value. It is not
// the real argument value that main passed in.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %v_0 [[UNDEF]]

// A real OpFAdd instruction adds one to the parameter of addOne. After this
// sum exists, the Value operand of DebugValue for the parameter obeys the
// contract.
// CHECK: [[SUM:%[0-9]+]] = OpFAdd %v4float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %v_0 [[SUM]]

// After addOne returns, the Value operand of DebugValue for `v` in main is a
// bare OpUndef value again. It is not the sum above, even though the shader
// knows that sum and uses it later in this function.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %v [[UNDEF]]

struct SSBO {
    float4 data;
};

[[vk::binding(1, 0)]]
RWStructuredBuffer<SSBO> ssbo;

void addOne(inout float4 v) {
    v = v + float4(1.0, 1.0, 1.0, 1.0);
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main() {
    float4 v = ssbo[0].data;
    addOne(v);
    ssbo[0].data = v;
}
