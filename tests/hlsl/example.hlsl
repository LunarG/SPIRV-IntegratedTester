// RUN: %dxc -T cs_6_0

// Capture the ID for the string "data" (the struct member name).
// CHECK: [[DATA_STR:%[0-9]+]] = OpString "data"

// Capture the DebugTypeMember that references the "data" string.
// CHECK: [[DATA_MEMBER:%[0-9]+]] = OpExtInst {{.*}} DebugTypeMember [[DATA_STR]]

// Verify a DebugLine is emitted before the store.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine

// Verify the AccessChain and the Store.
// CHECK: [[PTR:%[0-9]+]] = OpAccessChain {{.*}} %ssbo
// CHECK-NEXT: OpStore [[PTR]]

struct SSBO {
    float4 data;
};

[[vk::binding(1, 0)]]
RWStructuredBuffer<SSBO> ssbo;

[numthreads(1, 1, 1)]
void main() {
    ssbo[0].data = float4(0.0, 0.0, 0.0, 0.0);
}
