// RUN: %dxc -T cs_6_0 -E computeMain

// This shader is the HLSL restatement of
// inline_conditional_call_site_optimized.comp.glsl. The shader calls Foo two
// times, one time from each arm of an if statement, and dxc inlines Foo into
// both arms.
//
// This test is the converse of inline_control_flow.hlsl. In that test, the
// control flow sits inside the callee. In this test, the control flow sits in
// the caller, and dxc splices the callee into a block that runs under a
// condition.
//
// This test asserts one property. The debug information for each call site must
// still state which arm holds the call.
//
// Both calls pass the same argument to the same callee, and both produce the
// same arithmetic. The scope chain is therefore the only thing that can tell
// the two inlined copies apart.
//
// A compiler can key its inline record on the callee, and not on the call site.
// Such a compiler emits one DebugInlinedAt for both copies. A step through the
// else arm then reports the line of the if arm.
//
// This test identifies the two arms with no absolute line numbers. The if arm
// declares `b` only, and the else arm declares `c` only. The Parent operand of
// each variable therefore names the DebugLexicalBlock of its own arm. Each
// DebugInlinedAt must then point at one of those captured blocks.
//
// Note two shapes that are specific to dxc.
//
// First, dxc declares the else arm before the if arm. glslang uses the opposite
// order, so the captures below follow the dxc order.
//
// Second, dxc anchors the DebugLexicalBlock of each arm at the keyword that
// opens the arm, which is `if` or `} else {`. It does not anchor the block at
// the first statement of the arm, as glslang does. The Line operand of the block
// is therefore not the call line. This test takes the call line from the
// declaration of `b` or `c` instead, which is the statement that holds the
// call.

// These assertions capture the name strings. dxc emits the callee's strings before the caller's, and
// `c` before `b`.
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
// caller. dxc inserts this block as well, so the arms below are nested one level
// deeper than they are on glslang or slang.
// CHECK: [[MAIN:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[MAIN_NAME]]
// CHECK: [[MAIN_BLOCK:%[0-9]+]] = OpExtInst {{.*}} DebugLexicalBlock {{.*}} [[MAIN]]

// These assertions cover the lexical block of the else arm, and the variable
// that identifies it.
//
// The shader declares `c` on the same statement as the call, so the Line operand
// of `c` is the call line. This test captures that line one time, as
// [[ELSE_LINE]], and reuses it everywhere below. That reuse is what keeps this
// test free of absolute line numbers.
//
// The Parent of the block must be the body block of the caller. The arm is a
// scope nested in computeMain, and not a scope of its own.
// CHECK: [[ELSE_BLOCK:%[0-9]+]] = OpExtInst {{.*}} DebugLexicalBlock {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[MAIN_BLOCK]]
// CHECK: [[C:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[C_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[ELSE_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} [[ELSE_BLOCK]] {{.*}}

// This assertion covers the lexical block of the if arm, identified in the same
// way by `b`.
// CHECK: [[THEN_BLOCK:%[0-9]+]] = OpExtInst {{.*}} DebugLexicalBlock {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[MAIN_BLOCK]]
// CHECK: [[B:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[B_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[THEN_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} [[THEN_BLOCK]] {{.*}}

// The shader declares `a` outside the if statement, so `a` is parented to the
// body block of the caller, and not to either arm.
// CHECK: [[A:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[A_NAME]] {{.*}} [[MAIN_BLOCK]] {{.*}}

// Skip past dxc's own internal top-level wrapper DebugInlinedAt (it has
// no Inlined operand of its own) to reach the two for Foo's call sites.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugInlinedAt {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}}

// These two assertions are the heart of this test. There are two distinct
// DebugInlinedAt instructions, one for each call site.
//
// The two are distinct by construction, because two successive assertions
// cannot match the same instruction. Each one must name the block of its own
// arm, on the line of its own arm.
//
// One of these two assertions fails in three cases. The first case is that both
// call sites share one record. The second is that either one names the block of
// the other arm. The third is that either one names computeMain directly.
// CHECK: [[CALL_THEN:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[THEN_LINE]] [[THEN_BLOCK]] {{%[a-zA-Z_0-9]+}}
// CHECK: [[CALL_ELSE:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[ELSE_LINE]] [[ELSE_BLOCK]] {{%[a-zA-Z_0-9]+}}

// dxc wraps the entry point in a synthetic __dxc_setup function and every
// scope in the body carries that wrapper's DebugInlinedAt as a second
// operand.
//
// This test captures that wrapper for two reasons. It separates the wrapper
// from the arms below. It also lets the test assert the return to the scope of
// the caller, after the if statement.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[SETUP:%[0-9]+]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugFunctionDefinition [[SETUP]] %computeMain

// In the scope of the caller, the shader loads `a` one time, with a real value,
// and computes the condition from it. The load sits outside the if statement,
// so both arms share it.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN_BLOCK]] {{%[a-zA-Z_0-9]+}}
// CHECK: [[IN:%[0-9]+]] = OpAccessChain {{.*}} %buffer0 %int_0 %uint_0
// CHECK: [[VAL:%[0-9]+]] = OpLoad %uint [[IN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[A]] [[VAL]]
// CHECK: [[COND:%[0-9]+]] = OpUGreaterThan %bool [[VAL]] %uint_10

// The branch survives, so no compiler flattens the if statement to a select.
// This test captures its two target labels. Those captures pin every assertion
// below to the arm that it belongs to.
// CHECK: OpSelectionMerge [[MERGE_LABEL:%[a-zA-Z_0-9]+]] None
// CHECK: OpBranchConditional [[COND]] [[THEN_LABEL:%[a-zA-Z_0-9]+]] [[ELSE_LABEL:%[a-zA-Z_0-9]+]]

// This is the if arm. The first assertion requires the label. That requirement
// is the proof that the body of Foo sits inside the conditional.
//
// A pass can hoist that body above OpBranchConditional, so that it runs under no
// condition. The line of Foo then lands on an instruction that the source never
// reaches on this path, and these assertions cannot match in order.
//
// On entry, the line table is on the call statement, and the parameter of Foo
// takes the loaded value. The scope then moves down into the body block of Foo,
// and the line table must move to a line of Foo.
//
// dxc reports the body statement of Foo, and not its declaration, so no
// declaration anchors that line. This test captures it here, with the lineEnd
// operand wildcarded, and requires it in full in the else arm below. The two
// inlined copies therefore assert against each other.
// CHECK: [[THEN_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL_THEN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[THEN_LINE]] [[THEN_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[X]] [[VAL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO_BLOCK]] [[CALL_THEN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_BODY_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}}
// CHECK: [[THEN_RESULT:%[0-9]+]] = OpIMul %uint [[VAL]] %uint_2

// Execution leaves the inlined body. The scope must return to the arm that
// holds the call. That arm is the same block that the DebugInlinedAt of the call
// named, and it is not the body block of the caller. The line table must return
// to the call statement. `b` then takes the value from the inlined copy.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[THEN_BLOCK]] {{%[a-zA-Z_0-9]+}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[THEN_LINE]] [[THEN_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[B]] [[THEN_RESULT]]
// CHECK: [[OUT_THEN:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 %uint_0
// CHECK: OpStore [[OUT_THEN]] [[THEN_RESULT]]

// This test asserts the else arm in the same way, against its own captures. The
// callee line is now required in full, from the capture in the if arm. Both
// inlined copies must report the same line of Foo.
//
// [[ELSE_RESULT]] must be a different id from [[THEN_RESULT]]. That
// requirement is also the assertion that no pass merged the two inlined
// multiply instructions into one.
//
// The two instructions compute the same value from the same operand. A pass
// that hoists them, or that removes one as a common subexpression, leaves one
// copy. The line information of one arm only can then describe that copy.
// CHECK: [[ELSE_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL_ELSE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[ELSE_LINE]] [[ELSE_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[X]] [[VAL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO_BLOCK]] [[CALL_ELSE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_BODY_LINE]] [[FOO_BODY_LINE]]
// CHECK: [[ELSE_RESULT:%[0-9]+]] = OpIMul %uint [[VAL]] %uint_2
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[ELSE_BLOCK]] {{%[a-zA-Z_0-9]+}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[ELSE_LINE]] [[ELSE_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[C]] [[ELSE_RESULT]]
// CHECK: [[SUM:%[0-9]+]] = OpIAdd %uint [[ELSE_RESULT]] %uint_1
// CHECK: [[OUT_ELSE:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 %uint_0
// CHECK: OpStore [[OUT_ELSE]] [[SUM]]

// After the if statement, the scope is back where it was before the branch. The
// block of neither arm reaches outside the conditional.
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
    if (a > 10) {
        uint b = Foo(a);
        result[0] = b;
    } else {
        uint c = Foo(a);
        result[0] = c + 1;
    }
}
