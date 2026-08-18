// RUN: %dxc -T cs_6_0 -Od

// This shader is the same as inout_scalar.hlsl. This test turns off the dxc
// optimizations, so `v` in main and the parameter `v` of addOne are each a
// real Function-storage variable. A DebugDeclare instruction must describe `v`
// in main, and bind it to this real memory.
// CHECK: [[PARAM_V:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable
// CHECK: [[MAIN_V:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[MAIN_V]] %v

// The call to addOne is a real function call. The compiler does not inline it.
// After addOne returns, the value that addOne computed must reach the memory
// that DebugDeclare binds to `v` in main.
// CHECK: {{%[0-9]+}} = OpFunctionCall %void {{.*}}
// CHECK: [[BACK:%[0-9]+]] = OpLoad %float %v
// CHECK: {{%[0-9]+}} = OpAccessChain {{.*}}
// CHECK-NEXT: OpStore {{%[0-9]+}} [[BACK]]

// A DebugDeclare instruction must also describe the parameter `v` of addOne,
// and bind it to its own real memory.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[PARAM_V]] %v_0

// Inside addOne, a real OpFAdd instruction adds one to `v`. This sum must
// reach the memory that DebugDeclare binds to `v`.
// CHECK: [[SUM:%[0-9]+]] = OpFAdd %float
// CHECK: OpStore %v_0 [[SUM]]

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
