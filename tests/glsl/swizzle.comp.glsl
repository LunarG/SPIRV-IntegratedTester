// RUN: %glslang

// A DebugDeclare instruction describes `v` over real memory.
// CHECK: %v = OpVariable {{.*}} Function
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare {{%[0-9]+}} %v

// After the write `v.zyx = v.xyz * 2.0`, the new x, y, and z values must reach
// the memory that DebugDeclare binds to `v`. The shader stores each of the
// three values into the correct component of that memory.
//
// The order of these three stores does not matter. Each value must reach its
// own component.
// CHECK-DAG: [[MUL:%[0-9]+]] = OpVectorTimesScalar %v3float
// CHECK-DAG: [[PTR_Z:%[0-9]+]] = OpAccessChain {{.*}} %v %uint_2
// CHECK-DAG: [[EXTRACT_Z:%[0-9]+]] = OpCompositeExtract %float [[MUL]] 0
// CHECK-DAG: OpStore [[PTR_Z]] [[EXTRACT_Z]]
// CHECK-DAG: [[PTR_Y:%[0-9]+]] = OpAccessChain {{.*}} %v %uint_1
// CHECK-DAG: [[EXTRACT_Y:%[0-9]+]] = OpCompositeExtract %float [[MUL]] 1
// CHECK-DAG: OpStore [[PTR_Y]] [[EXTRACT_Y]]
// CHECK-DAG: [[PTR_X:%[0-9]+]] = OpAccessChain {{.*}} %v %uint_0
// CHECK-DAG: [[EXTRACT_X:%[0-9]+]] = OpCompositeExtract %float [[MUL]] 2
// CHECK-DAG: OpStore [[PTR_X]] [[EXTRACT_X]]

// The write `v.w = v.x + v.y` behaves the same way. The sum must reach the
// correct component of the memory for `v`.
// CHECK: [[SUM:%[0-9]+]] = OpFAdd %float
// CHECK: [[PTR_W:%[0-9]+]] = OpAccessChain {{.*}} %v %uint_3
// CHECK: OpStore [[PTR_W]] [[SUM]]

#version 450
layout(set = 0, binding = 1, std430) buffer SSBO {
    vec4 data;
};

void main() {
    vec4 v = data;
    v.zyx = v.xyz * 2.0;
    v.w = v.x + v.y;
    data = v.wzyx;
}
