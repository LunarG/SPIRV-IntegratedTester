// RUN: %dxc -T cs_6_0 -Od

// This shader is the same as swizzle.hlsl. This test turns off the dxc
// optimizations, so `v` is a real Function-storage variable. A DebugDeclare
// instruction must describe `v`, and bind it to this real memory.
// CHECK: [[V:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[V]] %v

// After the write `v.zyx = v.xyz * 2.0`, the updated vector must reach the
// memory that DebugDeclare binds to `v`. This vector holds the new x, y, and z
// values, together with the unchanged w value.
// CHECK: [[MUL:%[0-9]+]] = OpVectorTimesScalar %v3float
// CHECK: [[RELOAD:%[0-9]+]] = OpLoad %v4float %v
// CHECK: [[BLEND:%[0-9]+]] = OpVectorShuffle %v4float [[RELOAD]] [[MUL]] 6 5 4 3
// CHECK: OpStore %v [[BLEND]]

// The write `v.w = v.x + v.y` behaves the same way. The sum must reach the
// correct component of the memory for `v`.
// CHECK: [[SUM:%[0-9]+]] = OpFAdd %float
// CHECK: [[PTR_W:%[0-9]+]] = OpAccessChain {{.*}} %v %int_3
// CHECK: OpStore [[PTR_W]] [[SUM]]

struct SSBO {
    float4 data;
};

[[vk::binding(1, 0)]]
RWStructuredBuffer<SSBO> ssbo;

[numthreads(1, 1, 1)]
void main() {
    float4 v = ssbo[0].data;
    v.zyx = v.xyz * 2.0;
    v.w = v.x + v.y;
    ssbo[0].data = v.wzyx;
}
