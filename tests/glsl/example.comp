// RUN: %glslang

// Capture the ID for the string "data" (the struct member name).
// CHECK: [[DATA_STR:%[0-9]+]] = OpString "data"

// Capture the DebugTypeMember that references the "data" string.
// CHECK: [[DATA_MEMBER:%[0-9]+]] = OpExtInst {{.*}} DebugTypeMember [[DATA_STR]]

// Verify a DebugLine is emitted before the store.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine

// Verify the AccessChain and the Store.
// CHECK: [[PTR:%[0-9]+]] = OpAccessChain {{.*}} %_
// CHECK-NEXT: OpStore [[PTR]]

#version 450
layout(set = 0, binding = 1, std430) buffer SSBO {
    vec4 data;
};

void main() {
    data = vec4(0.0);
}
