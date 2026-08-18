// RUN: %slangc -O0

// This shader is the same [ForceUnroll] shader as
// inline_loop_call_site_unrolled.slang. This test disables the Slang optimizer.
//
// Slang still honors the attribute at this level. It unrolls the loop in full,
// into two straight-line copies. Slang does not inline Foo. Foo stays a real,
// separate function, and each unrolled copy calls it one time.
//
// This test is the one shape in the suite where unrolling and inlining come
// apart.

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

// `i` is real Function-storage memory in this test. A DebugDeclare must
// therefore describe it and bind to that memory, as well as the DebugValue
// instructions for each copy below.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare %i %_dbgvar_i {{%[a-zA-Z_0-9]+}}

// This is the first unrolled copy. The loop counter must read 0, both as a
// DebugValue and in the real store to its memory. The load must come from
// buffer0[0], and the value that the call returns must reach result[0].
//
// Slang unrolled the loop, so both access chains carry a constant index. Slang
// computes the destination pointer before it loads the source.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %i %uint_0
// CHECK: OpStore %_dbgvar_i %uint_0
// CHECK: [[OUT0:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 %uint_0
// CHECK: [[IN0:%[0-9]+]] = OpAccessChain {{.*}} %buffer0 %int_0 %uint_0
// CHECK: [[BUF0:%[0-9]+]] = OpLoad %uint [[IN0]]
// CHECK: [[CALL0:%[0-9]+]] = OpFunctionCall %uint %Foo [[BUF0]]
// CHECK: OpStore [[OUT0]] [[CALL0]]

// This is the second unrolled copy. The loop counter must read 1 here. This
// copy must read buffer0[1] and write result[1], and not the element of the
// first copy. It calls Foo through a second, separate real call.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %i %uint_1
// CHECK: OpStore %_dbgvar_i %uint_1
// CHECK: [[OUT1:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 %uint_1
// CHECK: [[IN1:%[0-9]+]] = OpAccessChain {{.*}} %buffer0 %int_0 %uint_1
// CHECK: [[BUF1:%[0-9]+]] = OpLoad %uint [[IN1]]
// CHECK: [[CALL1:%[0-9]+]] = OpFunctionCall %uint %Foo [[BUF1]]
// CHECK: OpStore [[OUT1]] [[CALL1]]

// After the last copy, the loop counter holds its exit value.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %i %uint_2

// The parameter of Foo arrives by value, and Slang copies it into real
// Function-storage memory. A DebugDeclare describes that memory. The real
// computation of Foo runs one time, inside Foo, and Foo returns the result.
// CHECK: %x = OpFunctionParameter %uint
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare %x_0 %_dbgvar_x {{%[a-zA-Z_0-9]+}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %x_0 %x
// CHECK: [[FOO_RESULT:%[0-9]+]] = OpIMul %uint %x
// CHECK: OpReturnValue [[FOO_RESULT]]

StructuredBuffer<uint> buffer0;
RWStructuredBuffer<uint> result;

uint Foo(uint x) {
    return x * 2;
}

[shader("compute")]
[numthreads(1,1,1)]
void computeMain(uint3 threadId : SV_DispatchThreadID)
{
    [ForceUnroll]
    for (uint i = 0; i < 2; i++) {
        result[i] = Foo(buffer0[i]);
    }
}
