// RUN: %glslang

// This shader is the same shadowing shader as
// inline_shadowed_local_optimized.comp.glsl, without the %spirv_opt step.
//
// This test inlines nothing, so the two locals named `scale` live in two
// different functions. Each one is its own Function-storage variable, with its
// own DebugDeclare, so a reader can tell them apart with ease.
//
// This behavior is the purpose of the variant. It fixes that both variables
// exist on their own before inlining. If this test passes and the optimized
// test fails, the fault is in the inliner, and not in glslang.

// Both variables share one name string, even in this test, where no reader can
// confuse them.
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[X_NAME:%[0-9]+]] = OpString "x"
// CHECK: [[SCALE_NAME:%[0-9]+]] = OpString "scale"

// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]]
// CHECK: [[X:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[X_NAME]]
// CHECK: [[MAIN:%[0-9]+]] = OpExtInst {{.*}} DebugFunction {{%[a-zA-Z_0-9]+}}

// The Parent operand is the one difference between the two shadowing
// variables. The variable of the callee is parented to Foo, and the variable of
// the caller is parented to main. Both Name operands are the same OpString,
// captured above.
// CHECK: [[SCALE_CALLEE:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[SCALE_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[FOO]] {{.*}}
// CHECK: [[SCALE_CALLER:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[SCALE_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[MAIN]] {{.*}}

// The debug information does not describe the call as an inlined call.
//
// Keep this guard in place, between a declaration assertion and a body
// assertion. A CHECK-NOT directive searches only the span between the two
// matches around it. The compiler declares DebugInlinedAt in the module
// preamble. At the end of the file, this guard matches nothing and always
// passes.
// CHECK-NOT: {{DebugInlinedAt}}

// In main, the `scale` of the caller is real Function-storage memory that holds
// 3. A DebugDeclare describes it and binds to that memory. The disassembler
// names it %scale_0, because the name is the same as the one in Foo.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[SCALE_CALLER]] %scale_0 {{%[a-zA-Z_0-9]+}}
// CHECK: OpStore %scale_0 %uint_3

// The shader makes a real call to Foo. It also reloads the `scale` of the
// caller from its own memory, and adds that value to the result.
// CHECK: [[CALL:%[0-9]+]] = OpFunctionCall %uint %Foo_u1_ %param
// CHECK: [[CALLER_SCALE:%[0-9]+]] = OpLoad %uint %scale_0
// CHECK: [[SUM:%[0-9]+]] = OpIAdd %uint [[CALL]] [[CALLER_SCALE]]
// CHECK: [[OUT:%[0-9]+]] = OpAccessChain
// CHECK: OpStore [[OUT]] [[SUM]]

// Inside Foo, the `scale` of the callee is a separate Function-storage variable
// that holds 5. Its own DebugDeclare binds to its own memory.
//
// There are two variables, two allocations, and two DebugDeclare instructions.
// The two variables share the name string only.
// CHECK: %x = OpFunctionParameter {{.*}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[X]] %x {{%[a-zA-Z_0-9]+}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[SCALE_CALLEE]] %scale {{%[a-zA-Z_0-9]+}}
// CHECK: OpStore %scale %uint_5

// The real computation of Foo reads both its parameter and its own
// `scale`.
// CHECK: [[FOO_X:%[0-9]+]] = OpLoad %uint %x
// CHECK: [[FOO_SCALE:%[0-9]+]] = OpLoad %uint %scale
// CHECK: [[PRODUCT:%[0-9]+]] = OpIMul %uint [[FOO_X]] [[FOO_SCALE]]
// CHECK: OpReturnValue [[PRODUCT]]

#version 450
layout(set = 0, binding = 0, std430) readonly buffer Buffer0 { uint buffer0[]; };
layout(set = 0, binding = 1, std430) buffer Result { uint result[]; };

uint Foo(uint x) {
    uint scale = 5;
    return x * scale;
}

void main() {
    uint scale = 3;
    result[0] = Foo(buffer0[0]) + scale;
}
