// RUN: %dxc -T cs_6_0

// A DebugLocalVariable instruction must describe each parameter of
// addOneToBoth, and another must describe each of `a` and `b` in main.
// CHECK: [[B_PARAM:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable
// CHECK: [[A_PARAM:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable
// CHECK: [[B_MAIN:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable
// CHECK: [[A_MAIN:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable

// After main loads `a` and `b`, the Value operand of DebugValue for each
// variable is the value that main loaded for that variable. The two variables
// do not exchange values.
// CHECK: [[LOAD_A:%[0-9]+]] = OpLoad %v4float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[A_MAIN]] [[LOAD_A]]
// CHECK: [[LOAD_B:%[0-9]+]] = OpLoad %v4float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[B_MAIN]] [[LOAD_B]]

// A real OpFAdd instruction adds one to each parameter. The Value operand of
// DebugValue for each parameter is its own sum. After the call, the Value
// operand for the matching variable in main is that same sum. The two
// variables do not exchange values.
// CHECK: [[SUM_A:%[0-9]+]] = OpFAdd %v4float [[LOAD_A]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[A_PARAM]] [[SUM_A]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[A_MAIN]] [[SUM_A]]
// CHECK: [[SUM_B:%[0-9]+]] = OpFAdd %v4float [[LOAD_B]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[B_PARAM]] [[SUM_B]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[B_MAIN]] [[SUM_B]]

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

[numthreads(1, 1, 1)]
void main() {
    float4 a = ssbo[0].dataA;
    float4 b = ssbo[0].dataB;
    addOneToBoth(a, b);
    ssbo[0].dataA = a;
    ssbo[0].dataB = b;
}
