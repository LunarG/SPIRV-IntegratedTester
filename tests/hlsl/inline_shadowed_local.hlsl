// RUN: %dxc -T cs_6_0 -E computeMain

// Foo declares a local named `scale`, and computeMain declares one too. dxc
// inlines Foo, so both locals sit in the same function body at the same time.
// The debug information is then the only thing that can tell them apart.
//
// The name cannot tell them apart. The module holds one OpString "scale" only,
// and both variables share it. The identity of each variable lives in the
// Parent operand of its DebugLocalVariable.
//
// dxc differs from glslang and slang here. It parents locals to a
// DebugLexicalBlock, and not directly to the DebugFunction, so the chain from
// variable to function is one link longer. This test asserts both links.

// Both variables share one name string.
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[SCALE_NAME:%[0-9]+]] = OpString "scale"
// CHECK: [[X_NAME:%[0-9]+]] = OpString "x"
// CHECK: [[MAIN_NAME:%[0-9]+]] = OpString "computeMain"

// These three assertions cover Foo, the lexical block of Foo, and the `scale`
// of the callee, which is parented to that block. The Parent of the block must
// be Foo.
//
// This test captures the declaration line of the callee here, and compares it
// against the line table below. This test needs no absolute line numbers.
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]]
// CHECK: [[FOO_BLOCK:%[0-9]+]] = OpExtInst {{.*}} DebugLexicalBlock {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[FOO]]
// CHECK: [[SCALE_CALLEE:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[SCALE_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[CALLEE_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} [[FOO_BLOCK]] {{.*}}
// CHECK: [[X:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[X_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[FOO]] {{.*}}

// These assertions cover the same three levels for the caller. The `scale` of
// the caller shares the name string captured above. It is parented to the block
// of computeMain, and not to the block of Foo. This difference is the whole
// contract that this test exists for.
// CHECK: [[MAIN:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[MAIN_NAME]]
// CHECK: [[MAIN_BLOCK:%[0-9]+]] = OpExtInst {{.*}} DebugLexicalBlock {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[MAIN]]
// CHECK: [[SCALE_CALLER:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[SCALE_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[MAIN_BLOCK]] {{.*}}

// dxc emits an internal top-level wrapper DebugInlinedAt, which has no Inlined
// operand of its own. The assertion below steps past that wrapper, to reach the
// one for the call site of Foo.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugInlinedAt {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}}
// CHECK: [[CALL:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALLER_LINE:%[a-zA-Z_0-9]+]] [[MAIN_BLOCK]] {{%[a-zA-Z_0-9]+}}

// In the scope of the caller, the `scale` of the caller holds 3. The
// DebugValue binds to [[SCALE_CALLER]]. This binding is the proof that the
// value reached the variable of the caller, and not the one of the callee.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN_BLOCK]] {{%[a-zA-Z_0-9]+}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[SCALE_CALLER]] %uint_3

// The line table must be on the call site here. This test captured
// [[CALLER_LINE]] above, from DebugInlinedAt. This assertion therefore also
// compares the "inlined from" line against the line that the line table
// reports for the call statement.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALLER_LINE]] [[CALLER_LINE]]
// CHECK: [[IN:%[0-9]+]] = OpAccessChain {{.*}} %buffer0 %int_0 %uint_0
// CHECK: [[VAL:%[0-9]+]] = OpLoad %uint [[IN]]

// Execution enters the inlined body of Foo. The function scope of Foo comes
// first, for the parameter. The lexical block of Foo comes next, for the body.
//
// The line table must enter the body of the callee, and must not stay on the
// call site. The line here is the line that declares the `scale` of the callee.
// If the inliner attributes the whole inlined body to the call site, stepping
// into Foo does not appear to enter it, and this assertion fails.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[X]] [[VAL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO_BLOCK]] [[CALL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALLEE_LINE]] [[CALLEE_LINE]]

// The `scale` of the callee holds 5, and its real multiply uses that
// value.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[SCALE_CALLEE]] %uint_5
// CHECK: [[PRODUCT:%[0-9]+]] = OpIMul %uint [[VAL]] %uint_5

// Execution leaves the inlined body. The scope returns to the block of the
// caller, and the line table returns to the statement line of the caller.
//
// The arithmetic after this point uses the 3 of the caller, and not the 5 of
// the callee. The two variables therefore stayed distinct across the inlined
// region.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN_BLOCK]] {{%[a-zA-Z_0-9]+}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALLER_LINE]] [[CALLER_LINE]]
// CHECK: [[SUM:%[0-9]+]] = OpIAdd %uint [[PRODUCT]] %uint_3
// CHECK: [[OUT:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 %uint_0
// CHECK: OpStore [[OUT]] [[SUM]]

StructuredBuffer<uint> buffer0;
RWStructuredBuffer<uint> result;

uint Foo(uint x) {
    uint scale = 5;
    return x * scale;
}

[numthreads(1,1,1)]
void computeMain(uint3 threadId : SV_DispatchThreadID)
{
    uint scale = 3;
    result[0] = Foo(buffer0[0]) + scale;
}
