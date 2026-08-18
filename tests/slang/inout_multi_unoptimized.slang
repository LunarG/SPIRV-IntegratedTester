// RUN: %slangc -O0

// This shader is the same as inout_multi.slang. This test turns off all of the
// slang optimizations. A DebugLocalVariable instruction must describe each of
// `a` and `b` in main, and another must describe each parameter of
// addOneToBoth.
// CHECK: %a_0 = OpExtInst {{.*}} DebugLocalVariable
// CHECK: %b_0 = OpExtInst {{.*}} DebugLocalVariable
// CHECK: %b_2 = OpExtInst {{.*}} DebugLocalVariable
// CHECK: %a_2 = OpExtInst {{.*}} DebugLocalVariable

// After main loads `a` and `b`, the Value operand of DebugValue for each
// variable is the value that main loaded for that variable. The two variables
// do not exchange values.
// CHECK: [[LOAD_A:%[0-9]+]] = OpLoad %v4float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %a_0 [[LOAD_A]]
// CHECK: [[LOAD_B:%[0-9]+]] = OpLoad %v4float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %b_0 [[LOAD_B]]

// After addOneToBoth returns, main reloads `a` and `b` from real memory. The
// Value operand of DebugValue for each variable is its own reloaded value. The
// two variables do not exchange values.
// CHECK: {{%[0-9]+}} = OpFunctionCall %void {{.*}}
// CHECK: [[RELOAD_B:%[0-9]+]] = OpLoad %v4float %b
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %b_0 [[RELOAD_B]]
// CHECK: [[RELOAD_A:%[0-9]+]] = OpLoad %v4float %a
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %a_0 [[RELOAD_A]]

// CHECK: %a_1 = OpFunctionParameter {{.*}}
// CHECK: %b_1 = OpFunctionParameter {{.*}}

// Inside addOneToBoth, the Value operand of DebugValue for each parameter is
// the real argument value that main passed in for that parameter.
// CHECK: [[PARAM_B:%[0-9]+]] = OpLoad %v4float %b_1
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %b_2 [[PARAM_B]]
// CHECK: [[PARAM_A:%[0-9]+]] = OpLoad %v4float %a_1
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %a_2 [[PARAM_A]]

// A real OpFAdd instruction adds one to each parameter. The Value operand of
// DebugValue for each parameter is its own sum.
// CHECK: [[SUM_A:%[0-9]+]] = OpFAdd %v4float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %a_2 [[SUM_A]]
// CHECK: [[SUM_B:%[0-9]+]] = OpFAdd %v4float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %b_2 [[SUM_B]]

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
