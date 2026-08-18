// RUN: %dxc -T cs_6_0 -Od

// This shader is the same as inout_multi.hlsl. This test turns off the dxc
// optimizations. All four variables are therefore real Function-storage
// variables: `a` and `b` in main, and the two parameters of addOneToBoth.
//
// A DebugDeclare instruction must describe `a` in main, and another must
// describe `b`. Each instruction binds its variable to this real memory.
// CHECK: [[PARAM_B:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable
// CHECK: [[PARAM_A:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable
// CHECK: [[MAIN_B:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable
// CHECK: [[MAIN_A:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[MAIN_A]] %a
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[MAIN_B]] %b

// The call to addOneToBoth is a real function call. The compiler does not
// inline it. After addOneToBoth returns, the value for each parameter must
// reach the memory that DebugDeclare binds to the same variable in main. The
// two variables do not exchange values.
// CHECK: {{%[0-9]+}} = OpFunctionCall %void {{.*}}
// CHECK: [[BACK_A:%[0-9]+]] = OpLoad %v4float %a
// CHECK: {{%[0-9]+}} = OpAccessChain {{.*}}
// CHECK-NEXT: OpStore {{%[0-9]+}} [[BACK_A]]
// CHECK: [[BACK_B:%[0-9]+]] = OpLoad %v4float %b
// CHECK: {{%[0-9]+}} = OpAccessChain {{.*}}
// CHECK-NEXT: OpStore {{%[0-9]+}} [[BACK_B]]

// A DebugDeclare instruction must also describe each parameter of
// addOneToBoth, and bind it to its own real memory.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[PARAM_A]] %a_0
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[PARAM_B]] %b_0

// Inside addOneToBoth, a real OpFAdd instruction adds one to each parameter.
// Each sum must reach the memory that DebugDeclare binds to the same
// parameter. The two parameters do not exchange values.
// CHECK: [[SUM_A:%[0-9]+]] = OpFAdd %v4float
// CHECK: OpStore %a_0 [[SUM_A]]
// CHECK: [[SUM_B:%[0-9]+]] = OpFAdd %v4float
// CHECK: OpStore %b_0 [[SUM_B]]

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
