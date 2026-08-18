// RUN: %glslang

// A DebugDeclare instruction describes `v` in main. This instruction binds
// `v` to real memory.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare {{%[0-9]+}} %v_0

// After addOne returns, the value that addOne computed must reach the memory
// that DebugDeclare binds to `v`.
// CHECK: {{%[0-9]+}} = OpFunctionCall %void {{.*}}
// CHECK: [[BACK:%[0-9]+]] = OpLoad %float
// CHECK: OpStore %v_0 [[BACK]]

// A DebugDeclare instruction must also describe the parameter `v` of addOne,
// and bind it to real memory. This test uses a plain float for `v`. The
// result does not depend on the vector type that the other inout test uses.
// CHECK: %v = OpFunctionParameter {{.*}}
// CHECK-NEXT: {{%[0-9]+}} = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare {{%[0-9]+}} %v {{%[0-9]+}}

// Inside addOne, a real OpFAdd instruction adds one to `v`. This sum must
// reach the memory that DebugDeclare binds to `v`.
// CHECK: [[SUM:%[0-9]+]] = OpFAdd %float
// CHECK: OpStore %v [[SUM]]

#version 450
layout(set = 0, binding = 1, std430) buffer SSBO {
    float data;
};

void addOne(inout float v) {
    v = v + 1.0;
}

void main() {
    float v = data;
    addOne(v);
    data = v;
}
