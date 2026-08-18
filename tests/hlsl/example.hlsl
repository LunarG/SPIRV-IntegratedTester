// RUN: %dxc -T cs_6_0

// The string "data" is the name of the struct member.
// CHECK: [[DATA_STR:%[0-9]+]] = OpString "data"

// The DebugTypeMember for the struct member names this string.
// CHECK: [[DATA_MEMBER:%[0-9]+]] = OpExtInst {{.*}} DebugTypeMember [[DATA_STR]]

// The compiler emits a DebugLine before the store.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine

// The store goes through an access chain into the buffer.
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
