// RUN: %slangc -O0

// This shader is the same two-call shader as two_functions_inlined.slang. This
// test disables the Slang optimizer. Foo and Bar both stay real, separate
// functions, and Slang inlines neither one.

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

// computeMain calls Foo through a real function call. It then calls Bar
// through a separate real function call. Both calls pass the real value of `a`.
// The real value that each call returns reaches its own slot of result.
// CHECK: [[A:%[0-9]+]] = OpLoad %uint
// CHECK: [[FOO_CALL:%[0-9]+]] = OpFunctionCall %uint %Foo [[A]]
// CHECK: OpStore {{%[0-9]+}} [[FOO_CALL]]
// CHECK: [[BAR_CALL:%[0-9]+]] = OpFunctionCall %uint %Bar [[A]]
// CHECK: OpStore {{%[0-9]+}} [[BAR_CALL]]

// The parameter of Foo is real Function-storage memory. A DebugDeclare
// instruction describes it. The computation of Foo runs here and multiplies by
// two, and Foo returns the result.
// CHECK: %x = OpFunctionParameter %uint
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}}
// CHECK: [[FOO_RESULT:%[0-9]+]] = OpIMul %uint %x
// CHECK: OpReturnValue [[FOO_RESULT]]

// The parameter of Bar is also real Function-storage memory. Its own
// DebugDeclare instruction describes it. The computation of Bar runs here and
// adds 100, and Bar returns the result.
// CHECK: %y = OpFunctionParameter %uint
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}}
// CHECK: [[BAR_RESULT:%[0-9]+]] = OpIAdd %uint %y
// CHECK: OpReturnValue [[BAR_RESULT]]

StructuredBuffer<uint> buffer0;
RWStructuredBuffer<uint> result;

uint Foo(uint x) {
    return x * 2;
}

uint Bar(uint y) {
    return y + 100;
}

[shader("compute")]
[numthreads(1,1,1)]
void computeMain(uint3 threadId : SV_DispatchThreadID)
{
    uint a = buffer0[0];
    result[0] = Foo(a);
    result[1] = Bar(a);
}
