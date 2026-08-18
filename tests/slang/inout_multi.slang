// RUN: %slangc

// A DebugLocalVariable instruction must describe each of `a` and `b` in main,
// and another must describe each parameter of addOneToBoth.
// CHECK: [[UNDEF:%[0-9]+]] = OpUndef %v4float
// CHECK: %a = OpExtInst {{.*}} DebugLocalVariable
// CHECK: %b = OpExtInst {{.*}} DebugLocalVariable
// CHECK: %b_0 = OpExtInst {{.*}} DebugLocalVariable
// CHECK: %a_0 = OpExtInst {{.*}} DebugLocalVariable

// After main loads `a` and `b`, the Value operand of DebugValue for each
// variable is the value that main loaded for that variable. The two variables
// do not exchange values.
// CHECK: [[LOAD_A:%[0-9]+]] = OpLoad %v4float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %a [[LOAD_A]]
// CHECK: [[LOAD_B:%[0-9]+]] = OpLoad %v4float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %b [[LOAD_B]]

// main calls addOneToBoth with the values of `a` and `b`. The Value operand of
// DebugValue for both parameters is the same bare OpUndef value. It is not the
// real argument values that main passed in.
//
// This is the known defect from the single-parameter inout test. It appears
// again here, one time for each parameter.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %b_0 [[UNDEF]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %a_0 [[UNDEF]]

// A real OpFAdd instruction adds one to each parameter. After these sums
// exist, the Value operand of DebugValue for each parameter obeys the
// contract. The two parameters do not exchange values.
// CHECK: [[SUM_A:%[0-9]+]] = OpFAdd %v4float [[LOAD_A]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %a_0 [[SUM_A]]
// CHECK: [[SUM_B:%[0-9]+]] = OpFAdd %v4float [[LOAD_B]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %b_0 [[SUM_B]]

// After addOneToBoth returns, the Value operand of DebugValue for `a` and for
// `b` in main is the same bare OpUndef value again. It is not the sums
// above.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %b [[UNDEF]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %a [[UNDEF]]

struct SSBO {
    float4 dataA;
    float4 dataB;
};

[[vk::binding(1, 0)]]
RWStructuredBuffer<SSBO> ssbo;

void addOneToBoth(inout float4 a, inout float4 b) {
    a = a + float4(1.0, 1.0, 1.0, 1.0);
    b = b + float4(1.0, 1.0, 1.0, 1.0);
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main() {
    float4 a = ssbo[0].dataA;
    float4 b = ssbo[0].dataB;
    addOneToBoth(a, b);
    ssbo[0].dataA = a;
    ssbo[0].dataB = b;
}
