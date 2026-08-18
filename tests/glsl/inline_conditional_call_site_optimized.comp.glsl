// RUN: %glslang && %spirv_opt %spv -O -o %spv

// The shader calls Foo two times, one time from each arm of an if statement, and
// a compiler inlines Foo into both arms.
//
// This test is the converse of inline_control_flow_optimized.comp.glsl. In that
// test, the control flow sits inside the callee. In this test, the control flow
// sits in the caller, and a compiler splices the callee into a block that runs
// under a condition.
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

// These assertions capture the name strings. glslang emits the callee's strings before the caller's,
// and `b` and `c` last, in source order.
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[X_NAME:%[0-9]+]] = OpString "x"
// CHECK: [[MAIN_NAME:%[0-9]+]] = OpString "main"
// CHECK: [[A_NAME:%[0-9]+]] = OpString "a"
// CHECK: [[B_NAME:%[0-9]+]] = OpString "b"
// CHECK: [[C_NAME:%[0-9]+]] = OpString "c"

// These assertions cover four items: the callee, its parameter, the caller, and
// `a` in the caller. All four are parented directly to a DebugFunction, because
// none of them sits inside a conditional.
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]]
// CHECK: [[X:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[X_NAME]] {{.*}} [[FOO]] {{.*}}
// CHECK: [[MAIN:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[MAIN_NAME]]
// CHECK: [[A:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[A_NAME]] {{.*}} [[MAIN]] {{.*}}

// These assertions cover the lexical block of the if arm, and the variable that
// identifies it.
//
// The shader declares `b` on the same statement as the call, so the Line operand
// of the block is also the call line. This test captures that line one time, as
// [[THEN_LINE]], and reuses it everywhere below. That reuse is what keeps this
// test free of absolute line numbers.
//
// The Parent of the block must be the DebugFunction of the caller. The arm is a
// scope nested in main, and not a scope of its own.
// CHECK: [[THEN_BLOCK:%[0-9]+]] = OpExtInst {{.*}} DebugLexicalBlock {{%[a-zA-Z_0-9]+}} [[THEN_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} [[MAIN]]
// CHECK: [[B:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[B_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[THEN_LINE]] {{%[a-zA-Z_0-9]+}} [[THEN_BLOCK]] {{.*}}

// This assertion covers the lexical block of the else arm, identified in the
// same way by `c`.
// CHECK: [[ELSE_BLOCK:%[0-9]+]] = OpExtInst {{.*}} DebugLexicalBlock {{%[a-zA-Z_0-9]+}} [[ELSE_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} [[MAIN]]
// CHECK: [[C:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[C_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[ELSE_LINE]] {{%[a-zA-Z_0-9]+}} [[ELSE_BLOCK]] {{.*}}

// These two assertions are the heart of this test. There are two distinct
// DebugInlinedAt instructions, one for each call site.
//
// The two are distinct by construction, because two successive assertions
// cannot match the same instruction. Each one must name the block of its own
// arm, on the line of its own arm.
//
// One of these two assertions fails in three cases. The first case is that both
// call sites share one record. The second is that either one names the block of
// the other arm. The third is that either one names main directly.
// CHECK: [[CALL_THEN:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[THEN_LINE]] [[THEN_BLOCK]]
// CHECK: [[CALL_ELSE:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[ELSE_LINE]] [[ELSE_BLOCK]]

// In the scope of the caller, the shader loads `a` one time, with a real value,
// and computes the condition from it. The load sits outside the if statement,
// so both arms share it.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: [[IN:%[0-9]+]] = OpAccessChain {{.*}} %int_0 %int_0
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
// takes the loaded value. The line table must then move to a line of Foo.
//
// glslang reports the body statement of Foo, and not its declaration, so no
// declaration anchors that line. This test captures it here, with the lineEnd
// operand wildcarded, and requires it in full in the else arm below. The two
// inlined copies therefore assert against each other.
// CHECK: [[THEN_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL_THEN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[THEN_LINE]] [[THEN_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[X]] [[VAL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_BODY_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}}
// CHECK: [[THEN_RESULT:%[0-9]+]] = OpIMul %uint [[VAL]] %uint_2

// Execution leaves the inlined body. The scope must return to the arm that
// holds the call. That arm is the same block that the DebugInlinedAt of the call
// named, and it is not main. The line table must return to the call statement.
// `b` then takes the value from the inlined copy.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[THEN_BLOCK]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[THEN_LINE]] [[THEN_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[B]] [[THEN_RESULT]]
// CHECK: [[OUT_THEN:%[0-9]+]] = OpAccessChain {{.*}} %int_0 %int_0
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
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_BODY_LINE]] [[FOO_BODY_LINE]]
// CHECK: [[ELSE_RESULT:%[0-9]+]] = OpIMul %uint [[VAL]] %uint_2
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[ELSE_BLOCK]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[ELSE_LINE]] [[ELSE_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[C]] [[ELSE_RESULT]]
// CHECK: [[SUM:%[0-9]+]] = OpIAdd %uint [[ELSE_RESULT]] %uint_1
// CHECK: [[OUT_ELSE:%[0-9]+]] = OpAccessChain {{.*}} %int_0 %int_0
// CHECK: OpStore [[OUT_ELSE]] [[SUM]]

// After the if statement, the scope is back to the function of the caller. The
// block of neither arm reaches outside the conditional.
// CHECK: [[MERGE_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]

#version 450
layout(set = 0, binding = 0, std430) readonly buffer Buffer0 { uint buffer0[]; };
layout(set = 0, binding = 1, std430) buffer Result { uint result[]; };

uint Foo(uint x) {
    return x * 2;
}

void main() {
    uint a = buffer0[0];
    if (a > 10) {
        uint b = Foo(a);
        result[0] = b;
    } else {
        uint c = Foo(a);
        result[0] = c + 1;
    }
}
