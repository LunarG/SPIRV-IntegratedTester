// RUN: %dxc -T cs_6_0 -E computeMain

// This shader is the HLSL restatement of
// inline_call_in_condition_optimized.comp.glsl. The shader calls Foo from the
// condition of an if statement, and not from either arm.
//
// This test is the companion to inline_conditional_call_site.hlsl, and its
// mirror image. In that test, the call sits inside an arm, and its inlined body
// must be scoped to that arm. In this test, the shader evaluates the call
// before the branch exists.
//
// The inlined body therefore lands in the header block, above
// OpSelectionMerge, and it runs on every path.
//
// The DebugInlinedAt of the call must name the enclosing scope, which is the
// body block of computeMain. It must not name the DebugLexicalBlock of either
// arm, because the header block is not inside either arm.
//
// A compiler can scope a condition-expression call to one of the arms. Such a
// compiler tells a debugger that the call happened inside a branch that
// execution can skip.
//
// Both arms declare a local, `b` or `c`, for one purpose: to make their
// lexical blocks identifiable by name.
//
// This test captures each block as the Parent of its own variable. Each block
// is also a distinct instruction from the body block of the caller. The
// requirement that the Scope of the call be [[MAIN_BLOCK]] is therefore the
// statement that the Scope is neither arm.
//
// That requirement matters more here than on glslang. dxc anchors the block of
// the if arm at the `{` on the `if` line. The block of the arm and the call
// site therefore report the same line, which is line 12 in both cases.
//
// The line numbers therefore cannot tell them apart. The scope id can. This
// test identifies the arms through their variables, and not by line.
//
// The call sits in the condition only. A second call inside an arm, with the
// same argument, merges into this one as a common subexpression, because the
// header block dominates both arms. The question of which call line survives
// such a merge is separate. It has no place here, because it obscures the
// scoping question.

// These assertions capture the name strings. dxc emits `c` before `b`.
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[X_NAME:%[0-9]+]] = OpString "x"
// CHECK: [[MAIN_NAME:%[0-9]+]] = OpString "computeMain"
// CHECK: [[C_NAME:%[0-9]+]] = OpString "c"
// CHECK: [[B_NAME:%[0-9]+]] = OpString "b"
// CHECK: [[A_NAME:%[0-9]+]] = OpString "a"

// These assertions cover the callee, the lexical block that dxc inserts for the
// body of the callee, and the parameter of the callee.
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]]
// CHECK: [[FOO_BLOCK:%[0-9]+]] = OpExtInst {{.*}} DebugLexicalBlock {{.*}} [[FOO]]
// CHECK: [[X:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[X_NAME]] {{.*}} [[FOO]] {{.*}}

// These assertions cover the caller, and the lexical block for the body of the
// caller. That block is the scope that the call site must name.
// CHECK: [[MAIN:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[MAIN_NAME]]
// CHECK: [[MAIN_BLOCK:%[0-9]+]] = OpExtInst {{.*}} DebugLexicalBlock {{.*}} [[MAIN]]

// These assertions cover the lexical block of each arm. The local that only
// that arm declares identifies each block, and each block is parented to the
// body block of the caller. This test captures both, so that the Scope of the
// call can be required to be neither of them.
// CHECK: [[ELSE_BLOCK:%[0-9]+]] = OpExtInst {{.*}} DebugLexicalBlock {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[MAIN_BLOCK]]
// CHECK: [[C:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[C_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[ELSE_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} [[ELSE_BLOCK]] {{.*}}
// CHECK: [[THEN_BLOCK:%[0-9]+]] = OpExtInst {{.*}} DebugLexicalBlock {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[MAIN_BLOCK]]
// CHECK: [[B:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[B_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[THEN_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} [[THEN_BLOCK]] {{.*}}

// The shader declares `a` outside the if statement, so `a` is parented to the
// body block of the caller, and not to either arm.
// CHECK: [[A:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[A_NAME]] {{.*}} [[MAIN_BLOCK]] {{.*}}

// dxc emits an internal top-level wrapper DebugInlinedAt, which has no Inlined
// operand of its own. The assertion below steps past that wrapper, to reach the
// one for the call site of Foo.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugInlinedAt {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}}

// This assertion is the heart of this test. There is one call site, so there is
// one DebugInlinedAt. Its Scope operand is the body block of the caller. It is
// not [[THEN_BLOCK]], and it is not [[ELSE_BLOCK]].
//
// The Line operand is the line of the condition. This test captures it here,
// and compares it against the line table below.
// CHECK: [[CALL:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALL_LINE:%[a-zA-Z_0-9]+]] [[MAIN_BLOCK]] {{%[a-zA-Z_0-9]+}}

// The debug information does not describe the call as an inlined call.
//
// Keep this guard in place, between a declaration assertion and a body
// assertion. A CHECK-NOT directive searches only the span between the two
// matches around it. The compiler declares DebugInlinedAt in the module
// preamble. At the end of the file, this guard matches nothing and always
// passes.
// CHECK-NOT: {{DebugInlinedAt}}

// dxc wraps the entry point in a synthetic __dxc_setup function. Every scope in
// the body carries the DebugInlinedAt of that wrapper as a second operand. This
// test captures that wrapper, so that it can assert the return after the if
// statement.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[SETUP:%[0-9]+]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugFunctionDefinition [[SETUP]] %computeMain

// In the scope of the caller, the shader loads `a` one time, with a real
// value.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN_BLOCK]] {{%[a-zA-Z_0-9]+}}
// CHECK: [[IN:%[0-9]+]] = OpAccessChain {{.*}} %buffer0 %int_0 %uint_0
// CHECK: [[VAL:%[0-9]+]] = OpLoad %uint [[IN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[A]] [[VAL]]

// The inlined body of Foo sits in the header block. Every assertion from here
// to the OpBranchConditional below comes before the branch.
//
// That order is the proof that no pass sank the body into an arm. The body also
// sits above OpSelectionMerge, which is the proof that it runs on every path.
//
// On entry, the line table is on the condition, and the parameter of Foo takes
// the loaded value. The scope then moves down into the body block of Foo, and
// the line table must leave the line of the condition.
//
// dxc reports the body statement of Foo, and not its declaration, so no
// declaration anchors that line. This test has one inlined copy, so no second
// copy exists to compare against. The requirement is therefore a CHECK-NOT
// guard over the region up to the multiply.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[X]] [[VAL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO_BLOCK]] [[CALL]]
// CHECK-NOT: DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: [[FOO_RESULT:%[0-9]+]] = OpIMul %uint [[VAL]] %uint_2

// Execution leaves the inlined body. The scope returns to the body block of the
// caller, and the line table returns to the condition. The condition tests the
// value that Foo produced.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN_BLOCK]] {{%[a-zA-Z_0-9]+}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: [[COND:%[0-9]+]] = OpUGreaterThan %bool [[FOO_RESULT]] %uint_10

// The branch appears only at this point.
// CHECK: OpSelectionMerge [[MERGE_LABEL:%[a-zA-Z_0-9]+]] None
// CHECK: OpBranchConditional [[COND]] [[THEN_LABEL:%[a-zA-Z_0-9]+]] [[ELSE_LABEL:%[a-zA-Z_0-9]+]]

// Each arm enters its own lexical block, and computes its own value from the
// same loaded `a`. Neither arm holds any part of Foo. The condition above
// consumed the callee in full.
// CHECK: [[THEN_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[THEN_BLOCK]] {{%[a-zA-Z_0-9]+}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[THEN_LINE]] [[THEN_LINE]]
// CHECK: [[B_VAL:%[0-9]+]] = OpIMul %uint [[VAL]] %uint_3
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[B]] [[B_VAL]]
// CHECK: [[OUT_THEN:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 %uint_0
// CHECK: OpStore [[OUT_THEN]] [[B_VAL]]

// CHECK: [[ELSE_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[ELSE_BLOCK]] {{%[a-zA-Z_0-9]+}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[ELSE_LINE]] [[ELSE_LINE]]
// CHECK: [[C_VAL:%[0-9]+]] = OpIAdd %uint [[VAL]] %uint_1
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[C]] [[C_VAL]]
// CHECK: [[OUT_ELSE:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 %uint_0
// CHECK: OpStore [[OUT_ELSE]] [[C_VAL]]

// Past the if, the scope is back where it was before the branch.
// CHECK: [[MERGE_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[SETUP]]

StructuredBuffer<uint> buffer0;
RWStructuredBuffer<uint> result;

uint Foo(uint x) {
    return x * 2;
}

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
