// RUN: %dxc -T cs_6_0 -E computeMain -Od

// This shader is the same two-call shader as two_functions_inlined.hlsl. This
// test turns off the dxc optimizations. Foo and Bar both stay real, separate
// functions, and dxc inlines neither one.

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
// memory. computeMain reloads the real value of `a` and stores it into a real
// argument slot. It then calls Foo through that slot. The real value that Foo
// returns reaches result[0].
// CHECK: [[A:%[0-9]+]] = OpLoad %uint %a
// CHECK: OpStore %param_var_x [[A]]
// CHECK: [[FOO_CALL:%[0-9]+]] = OpFunctionCall %uint %Foo %param_var_x
// CHECK: OpStore {{%[0-9]+}} [[FOO_CALL]]

// computeMain reloads `a` a second time and stores it into a separate real
// argument slot. It then calls Bar through that slot. The real value that Bar
// returns reaches result[1].
// CHECK: [[A_RELOAD:%[0-9]+]] = OpLoad %uint %a
// CHECK: OpStore %param_var_y [[A_RELOAD]]
// CHECK: [[BAR_CALL:%[0-9]+]] = OpFunctionCall %uint %Bar %param_var_y
// CHECK: OpStore {{%[0-9]+}} [[BAR_CALL]]

// The parameter of Foo is real Function-storage memory. A DebugDeclare
// instruction describes it. The computation of Foo runs here and multiplies by
// two, and Foo returns the result.
// CHECK: %x = OpFunctionParameter {{.*}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare {{%[a-zA-Z_0-9]+}} %x {{%[a-zA-Z_0-9]+}}
// CHECK: [[X:%[0-9]+]] = OpLoad %uint %x
// CHECK: [[FOO_RESULT:%[0-9]+]] = OpIMul %uint [[X]]
// CHECK: OpReturnValue [[FOO_RESULT]]

// The parameter of Bar is also real Function-storage memory. Its own
// DebugDeclare instruction describes it. The computation of Bar runs here and
// adds 100, and Bar returns the result.
// CHECK: %y = OpFunctionParameter {{.*}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare {{%[a-zA-Z_0-9]+}} %y {{%[a-zA-Z_0-9]+}}
// CHECK: [[Y:%[0-9]+]] = OpLoad %uint %y
// CHECK: [[BAR_RESULT:%[0-9]+]] = OpIAdd %uint [[Y]]
// CHECK: OpReturnValue [[BAR_RESULT]]

StructuredBuffer<uint> buffer0;
RWStructuredBuffer<uint> result;

uint Foo(uint x) {
    return x * 2;
}

uint Bar(uint y) {
    return y + 100;
}

[numthreads(1,1,1)]
void computeMain(uint3 threadId : SV_DispatchThreadID)
{
    uint a = buffer0[0];
    result[0] = Foo(a);
    result[1] = Bar(a);
}
