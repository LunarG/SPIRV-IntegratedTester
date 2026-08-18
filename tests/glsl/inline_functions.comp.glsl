// RUN: %glslang

// This shader is a GLSL restatement of the "Inline Functions" checklist item
// of issue #9: https://godbolt.org/z/hbzq4zz71
//
// The glslang default never inlines (see CLAUDE.md). Foo stays a real,
// separate function in this test. glslang does not inline Foo into main.

// Foo has its own DebugFunction. This test asserts this fact for one reason
// only: to anchor the guard below. The guard needs a declaration assertion
// above it, and a body assertion beneath it. Its region then covers the span
// where the compiler declares a DebugInlinedAt.
// CHECK: [[FOO_DECL_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugFunction [[FOO_DECL_NAME]]

// The debug information does not describe the call as an inlined call.
//
// Keep this guard in place, between a declaration assertion and a body
// assertion. A CHECK-NOT directive searches only the span between the two
// matches around it. The compiler declares DebugInlinedAt in the module
// preamble. At the end of the file, this guard matches nothing and always
// passes.
// CHECK-NOT: {{DebugInlinedAt}}

// The shader loads `a` from the buffer one time, into real memory.
// CHECK: [[BUFVAL:%[0-9]+]] = OpLoad %uint
// CHECK: OpStore %a [[BUFVAL]]

// glslang passes function arguments by pointer to real Function-storage
// memory. The call `Foo(a)` reloads the real value of `a`. It stores this
// value into a real argument slot, and not a placeholder. It then calls Foo
// through that slot.
// CHECK: [[A:%[0-9]+]] = OpLoad %uint %a
// CHECK: OpStore %param [[A]]
// CHECK: {{%[0-9]+}} = OpFunctionCall %uint %Foo_u1_ %param

// The call `Foo(a + 1)` behaves the same way. It uses its own argument slot
// and its own computed value.
// CHECK: [[A_RELOAD:%[0-9]+]] = OpLoad %uint %a
// CHECK: [[A_PLUS_1:%[0-9]+]] = OpIAdd %uint [[A_RELOAD]]
// CHECK: OpStore %param_0 [[A_PLUS_1]]
// CHECK: {{%[0-9]+}} = OpFunctionCall %uint %Foo_u1_ %param_0

// The parameter of Foo is real Function-storage memory. A DebugDeclare
// instruction must describe this parameter, and bind it to this real
// memory.
// CHECK: %x = OpFunctionParameter {{.*}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare {{%[a-zA-Z_0-9]+}} %x {{%[a-zA-Z_0-9]+}}

// Inside Foo, a real OpLoad instruction reads the parameter. A real OpIMul
// instruction then computes the result from that value.
// CHECK: [[X:%[0-9]+]] = OpLoad %uint %x
// CHECK: OpIMul %uint [[X]]

#version 450
layout(set = 0, binding = 0, std430) readonly buffer Buffer0 { uint buffer0[]; };
layout(set = 0, binding = 1, std430) buffer Result { uint result[]; };

uint Foo(uint x) {
    return x * 2;
}

void main() {
    uint a = buffer0[0];
    result[0] = Foo(a);
    result[1] = Foo(a + 1);
}
