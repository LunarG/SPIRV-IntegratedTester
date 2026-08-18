// RUN: %slangc

// The string "data" is the name of the struct member.
// CHECK: [[DATA_STR:%[0-9]+]] = OpString "data"

// The DebugTypeMember for the struct member names this string.
// CHECK: [[DATA_MEMBER:%[0-9]+]] = OpExtInst {{.*}} DebugTypeMember [[DATA_STR]]

// The compiler emits a DebugLine before the store.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine

// The store goes through two chained access chains into the buffer.
// CHECK: [[PTR1:%[0-9]+]] = OpAccessChain {{.*}} %ssbo
// CHECK-NEXT: [[PTR2:%[0-9]+]] = OpAccessChain {{.*}} [[PTR1]]
// CHECK-NEXT: OpStore [[PTR2]]

struct SSBO {
    float4 data;
};

[[vk::binding(1, 0)]]
RWStructuredBuffer<SSBO> ssbo;

[shader("compute")]
[numthreads(1, 1, 1)]
void main() {
    ssbo[0].data = float4(0.0);
}
