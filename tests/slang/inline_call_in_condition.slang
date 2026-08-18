// RUN: %slangc

// This shader is the Slang restatement of
// inline_call_in_condition_optimized.comp.glsl. The shader calls Foo from the
// condition of an if statement, and not from either arm.
//
// This test is the companion to inline_conditional_call_site.slang, and its
// mirror image. In that test, the call sits inside an arm. In this test, the
// shader evaluates the call before the branch exists.
//
// The inlined body therefore lands in the header block, above
// OpSelectionMerge, and it runs on every path. Its DebugInlinedAt must name the
// enclosing scope, and its Line must be the line of the condition.
//
// Slang emits no DebugLexicalBlock at any optimization level. It therefore has
// no scope for an arm, and no wrong scope for a condition-expression call.
//
// The scope stays the DebugFunction of computeMain across the whole construct.
// `b` and `c` are parented to that scope, even though the shader declares them
// inside the arms.
//
// That shape is conformant. Only glslang and dxc can answer the sharp form of
// the question in this test.
//
// This test asserts the shape that Slang does have. There is one DebugInlinedAt
// on the line of the condition. The inlined body sits above the branch, and both
// arms run in the scope of the caller.
//
// Each arm still declares its own local, `b` or `c`, so that the three files
// share one shader.
//
// The call sits in the condition only. A second call inside an arm, with the
// same argument, merges into this one, because the header block dominates both
// arms.

// These assertions capture the name strings. Slang emits the strings of the
// caller before the strings of the callee.
// CHECK: [[MAIN_NAME:%[0-9]+]] = OpString "computeMain"
// CHECK: [[A_NAME:%[0-9]+]] = OpString "a"
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[X_NAME:%[0-9]+]] = OpString "x"
// CHECK: [[B_NAME:%[0-9]+]] = OpString "b"
// CHECK: [[C_NAME:%[0-9]+]] = OpString "c"

// These assertions cover the caller and its `a`.
// CHECK: [[MAIN:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[MAIN_NAME]]
// CHECK: %a = OpExtInst {{.*}} DebugLocalVariable [[A_NAME]] {{.*}} [[MAIN]] {{.*}}

// These assertions cover the callee and its parameter.
//
// This test captures the declaration line of Foo here. Slang reports that line
// as the first line inside the inlined copy. It does not report the body
// statement of Foo.
//
// That line is therefore a positive anchor for the callee line below. This
// compiler needs no CHECK-NOT guard for it.
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[FOO_LINE:%[a-zA-Z_0-9]+]] {{.*}}
// CHECK: %x = OpExtInst {{.*}} DebugLocalVariable [[X_NAME]] {{.*}} [[FOO]] {{.*}}

// These assertions cover the local of each arm. Both are parented to
// computeMain, and not to an arm. Each one carries the line of the arm that
// declares it.
// CHECK: %b = OpExtInst {{.*}} DebugLocalVariable [[B_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[THEN_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} [[MAIN]] {{.*}}
// CHECK: %c = OpExtInst {{.*}} DebugLocalVariable [[C_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[ELSE_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} [[MAIN]] {{.*}}

// There is one call site, so there is one DebugInlinedAt. It is scoped to
// computeMain, and it carries the line of the condition. This test compares that
// line against the line table below.
// CHECK: [[CALL:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALL_LINE:%[a-zA-Z_0-9]+]] [[MAIN]]

// The debug information does not describe the call as an inlined call.
//
// Keep this guard in place, between a declaration assertion and a body
// assertion. A CHECK-NOT directive searches only the span between the two
// matches around it. The compiler declares DebugInlinedAt in the module
// preamble. At the end of the file, this guard matches nothing and always
// passes.
// CHECK-NOT: {{DebugInlinedAt}}

// In the scope of the caller, the shader loads `a` one time, with a real
// value. Slang emits each DebugValue two times. This test asserts the first one
// only.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugFunctionDefinition [[MAIN]] %computeMain
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: [[IN:%[0-9]+]] = OpAccessChain {{.*}} %buffer0 %int_0 %int_0
// CHECK: [[VAL:%[0-9]+]] = OpLoad %uint [[IN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %a [[VAL]]

// The inlined body of Foo sits in the header block. Every assertion from here
// to the OpBranchConditional below comes before the branch.
//
// That order is the proof that no pass sank the body into an arm. The body also
// sits above OpSelectionMerge, which is the proof that it runs on every path.
//
// The line table must move at once to a line of Foo. On this compiler, that
// line is the declaration line of Foo, captured above. This test therefore
// states the requirement positively, and not as a CHECK-NOT guard.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_LINE]] [[FOO_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %x [[VAL]]
// CHECK: [[FOO_RESULT:%[0-9]+]] = OpIMul %uint [[VAL]] %uint_2

// Execution leaves the inlined body. The scope returns to the caller, and the
// line table returns to the condition. The condition tests the value that Foo
// produced.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: [[COND:%[0-9]+]] = OpUGreaterThan %bool [[FOO_RESULT]] %uint_10

// The branch appears only at this point.
// CHECK: OpSelectionMerge [[MERGE_LABEL:%[a-zA-Z_0-9]+]] None
// CHECK: OpBranchConditional [[COND]] [[THEN_LABEL:%[a-zA-Z_0-9]+]] [[ELSE_LABEL:%[a-zA-Z_0-9]+]]

// Each arm runs in the scope of the caller, because Slang has no scope for an
// arm to enter. Each arm still runs on its own line, and computes its own value
// from the same loaded `a`.
//
// Neither arm holds any part of Foo. The condition above consumed the callee in
// full.
// CHECK: [[THEN_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[THEN_LINE]] [[THEN_LINE]]
// CHECK: [[B_VAL:%[a-zA-Z_0-9]+]] = OpIMul %uint [[VAL]] %uint_3
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %b [[B_VAL]]
// CHECK: [[OUT_THEN:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 %int_0
// CHECK: OpStore [[OUT_THEN]] [[B_VAL]]

// CHECK: [[ELSE_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[ELSE_LINE]] [[ELSE_LINE]]
// CHECK: [[C_VAL:%[a-zA-Z_0-9]+]] = OpIAdd %uint [[VAL]] %uint_1
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %c [[C_VAL]]
// CHECK: [[OUT_ELSE:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 %int_0
// CHECK: OpStore [[OUT_ELSE]] [[C_VAL]]

// After the if statement, the scope is still the scope of the caller.
// CHECK: [[MERGE_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]

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
    if (Foo(a) > 10) {
        uint b = a * 3;
        result[0] = b;
    } else {
        uint c = a + 1;
        result[0] = c;
    }
}
