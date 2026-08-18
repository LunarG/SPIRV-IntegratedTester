// RUN: %glslang

// One DebugDeclare instruction describes `a` in main, and another describes
// `b`. Each instruction binds its variable to real memory.
// CHECK-DAG: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare {{%[0-9]+}} %a_0
// CHECK-DAG: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare {{%[0-9]+}} %b_0

// After addOneToBoth returns, the value for each parameter must reach the
// memory that DebugDeclare binds to the same variable in main. The two
// variables do not exchange values.
// CHECK: {{%[0-9]+}} = OpFunctionCall %void {{.*}}
// CHECK-DAG: [[BACK_A:%[0-9]+]] = OpLoad %v4float %param
// CHECK-DAG: OpStore %a_0 [[BACK_A]]
// CHECK-DAG: [[BACK_B:%[0-9]+]] = OpLoad %v4float %param_0
// CHECK-DAG: OpStore %b_0 [[BACK_B]]

// A DebugDeclare instruction must also describe each parameter of
// addOneToBoth, and bind it to real memory.
// CHECK: %a = OpFunctionParameter {{.*}}
// CHECK-NEXT: %b = OpFunctionParameter {{.*}}
// CHECK-NEXT: {{%[0-9]+}} = OpLabel
// CHECK-DAG: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare {{%[0-9]+}} %a {{%[0-9]+}}
// CHECK-DAG: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare {{%[0-9]+}} %b {{%[0-9]+}}

// Inside addOneToBoth, a real OpFAdd instruction adds one to each parameter.
// Each sum must reach the memory that DebugDeclare binds to the same
// parameter. The two parameters do not exchange values.
// CHECK-DAG: [[LOAD_A:%[0-9]+]] = OpLoad %v4float %a
// CHECK-DAG: [[SUM_A:%[0-9]+]] = OpFAdd %v4float [[LOAD_A]]
// CHECK-DAG: OpStore %a [[SUM_A]]
// CHECK-DAG: [[LOAD_B:%[0-9]+]] = OpLoad %v4float %b
// CHECK-DAG: [[SUM_B:%[0-9]+]] = OpFAdd %v4float [[LOAD_B]]
// CHECK-DAG: OpStore %b [[SUM_B]]

#version 450
layout(set = 0, binding = 1, std430) buffer SSBO {
    vec4 dataA;
    vec4 dataB;
};

void addOneToBoth(inout vec4 a, inout vec4 b) {
    a = a + vec4(1.0, 1.0, 1.0, 1.0);
    b = b + vec4(1.0, 1.0, 1.0, 1.0);
}

void main() {
    vec4 a = dataA;
    vec4 b = dataB;
    addOneToBoth(a, b);
    dataA = a;
    dataB = b;
}
