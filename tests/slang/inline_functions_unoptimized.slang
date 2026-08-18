// RUN: %slangc -O0

// This shader is the "Inline Functions" checklist item of issue #9. This test
// disables the Slang optimizer. Foo stays a real, separate function, and Slang
// does not inline it into computeMain.

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

// computeMain calls Foo through a real function call, one time for `Foo(a)`
// and one time for `Foo(a + 1)`. Each call passes a real value as its argument,
// and not a placeholder.
// CHECK: [[A:%[0-9]+]] = OpLoad %uint
// CHECK: {{%[0-9]+}} = OpFunctionCall %uint %Foo [[A]]
// CHECK: [[A_PLUS_1:%[0-9]+]] = OpIAdd %uint [[A]]
// CHECK: {{%[0-9]+}} = OpFunctionCall %uint %Foo [[A_PLUS_1]]

// The parameter of Foo is real Function-storage memory. A DebugDeclare
// instruction must describe this parameter, and bind it to this real
// memory.
// CHECK: %x = OpFunctionParameter %uint
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}}

// Inside Foo, a real OpIMul instruction computes the result from the real
// parameter.
// CHECK: OpIMul %uint %x

StructuredBuffer<uint> buffer0;
RWStructuredBuffer<uint> result;

uint Foo(uint x) {
    return x * 2;
}

[shader("compute")]
[numthreads(1,1,1)]
void computeMain(uint3 threadId : SV_DispatchThreadID)
{
    uint a = buffer0[0];
    result[0] = Foo(a);
    result[1] = Foo(a + 1);
}
