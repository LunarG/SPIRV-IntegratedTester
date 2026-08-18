// RUN: %dxc -T cs_6_0 -E computeMain -Od

// This shader is the "Inline Functions" checklist item of issue #9. This test
// turns off the dxc optimizations. Foo stays a real, separate function, and
// dxc does not inline it into computeMain.

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

// At -Od, dxc passes function arguments by pointer to real Function-storage
// memory. The call `Foo(a)` reloads the real value of `a`. It stores this
// value into a real argument slot, and not a placeholder. It then calls Foo
// through that slot.
// CHECK: [[A:%[0-9]+]] = OpLoad %uint %a
// CHECK: OpStore %param_var_x [[A]]
// CHECK: {{%[0-9]+}} = OpFunctionCall %uint %Foo %param_var_x

// The call `Foo(a + 1)` behaves the same way. It uses its own argument slot
// and its own computed value.
// CHECK: [[A_RELOAD:%[0-9]+]] = OpLoad %uint %a
// CHECK: [[A_PLUS_1:%[0-9]+]] = OpIAdd %uint [[A_RELOAD]]
// CHECK: OpStore %param_var_x_0 [[A_PLUS_1]]
// CHECK: {{%[0-9]+}} = OpFunctionCall %uint %Foo %param_var_x_0

// The parameter of Foo is real Function-storage memory. A DebugDeclare
// instruction must describe this parameter, and bind it to this real
// memory.
// CHECK: %x = OpFunctionParameter {{.*}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare {{%[a-zA-Z_0-9]+}} %x {{%[a-zA-Z_0-9]+}}

// Inside Foo, a real OpLoad instruction reads the parameter. A real OpIMul
// instruction then computes the result from that value.
// CHECK: [[X:%[0-9]+]] = OpLoad %uint %x
// CHECK: OpIMul %uint [[X]]

StructuredBuffer<uint> buffer0;
RWStructuredBuffer<uint> result;

uint Foo(uint x) {
    return x * 2;
}

[numthreads(1,1,1)]
void computeMain(uint3 threadId : SV_DispatchThreadID)
{
    uint a = buffer0[0];
    result[0] = Foo(a);
    result[1] = Foo(a + 1);
}
