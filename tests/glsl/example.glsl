// RUN: %glslang -S comp

// The string "data" is the name of the struct member.
// CHECK: [[DATA_STR:%[0-9]+]] = OpString "data"

// The DebugTypeMember for the struct member names this string.
// CHECK: [[DATA_MEMBER:%[0-9]+]] = OpExtInst {{.*}} DebugTypeMember [[DATA_STR]]

// The compiler emits a DebugLine before the store.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine

// The store goes through an access chain into the buffer.
// CHECK: [[PTR:%[0-9]+]] = OpAccessChain {{.*}} %_
// CHECK-NEXT: OpStore [[PTR]]

#version 450
layout(set = 0, binding = 1, std430) buffer SSBO {
    vec4 data;
};

void main() {
    data = vec4(0.0);
}
