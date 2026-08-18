// RUN: %slangc

// This shader is the Slang restatement of
// inline_conditional_call_site_optimized.comp.glsl. The shader calls Foo two
// times, one time from each arm of an if statement, and Slang inlines Foo into
// both arms.
//
// This test is the converse of inline_control_flow.slang. In that test, the
// control flow sits inside the callee. In this test, the control flow sits in
// the caller, and Slang splices the callee into a block that runs under a
// condition.
//
// This test asserts one property. The debug information for each call site must
// still state which arm holds the call.
//
// Both calls pass the same argument to the same callee, and both produce the
// same arithmetic. The inline record is therefore the only thing that can tell
// the two inlined copies apart.
//
// A compiler can key that record on the callee, and not on the call site. Such
// a compiler emits one DebugInlinedAt for both copies. A step through the else
// arm then reports the line of the if arm.
//
// Slang emits no DebugLexicalBlock, so it has no scope for each arm to name.
// glslang and dxc both emit one. The DebugInlinedAt of both call sites therefore
// names the DebugFunction of computeMain directly.
//
// That shape is conformant. The spec requires only that Scope be "a lexical
// scope that contains Line", and the enclosing function does contain it. This
// test therefore does not require a scope for each arm.
//
// This test does require that the two call sites stay distinct. There must be
// two separate DebugInlinedAt instructions, and each one must carry the call
// line of its own arm. This test takes those lines from the declaration of `b`
// and of `c`, which sit on the call statements themselves, one for each arm.
// This test uses no absolute line numbers.

// These assertions capture the name strings. Slang emits the caller's strings before the callee's, and
// interleaves `b` and `c` around them.
// CHECK: [[MAIN_NAME:%[0-9]+]] = OpString "computeMain"
// CHECK: [[A_NAME:%[0-9]+]] = OpString "a"
// CHECK: [[B_NAME:%[0-9]+]] = OpString "b"
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[X_NAME:%[0-9]+]] = OpString "x"
// CHECK: [[C_NAME:%[0-9]+]] = OpString "c"

// These assertions cover the caller and two locals. The shader declares one
// local outside the if statement, and one inside it.
//
// All three are parented directly to the DebugFunction of computeMain. This
// module has no lexical block, so `a` and `b` share a parent, even though `b`
// alone sits inside the conditional.
//
// The line that declares `b` is the call line of the if arm. This test captures
// that line for reuse below.
// CHECK: [[MAIN:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[MAIN_NAME]]
// CHECK: %a = OpExtInst {{.*}} DebugLocalVariable [[A_NAME]] {{.*}} [[MAIN]] {{.*}}
// CHECK: %b = OpExtInst {{.*}} DebugLocalVariable [[B_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[THEN_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} [[MAIN]] {{.*}}

// These assertions cover the callee and its parameter.
//
// This test captures the declaration line of Foo here. Slang reports that line
// as the first line inside each inlined copy. It does not report the body
// statement of Foo. That line therefore serves as a positive anchor for the
// callee line further down.
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[FOO_LINE:%[a-zA-Z_0-9]+]] {{.*}}
// CHECK: %x = OpExtInst {{.*}} DebugLocalVariable [[X_NAME]] {{.*}} [[FOO]] {{.*}}

// This assertion covers the local of the else arm, and with it the call line of
// that arm.
// CHECK: %c = OpExtInst {{.*}} DebugLocalVariable [[C_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[ELSE_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} [[MAIN]] {{.*}}

// These two assertions are the heart of this test. There are two distinct
// DebugInlinedAt instructions, one for each call site.
//
// The two are distinct by construction, because two successive assertions
// cannot match the same instruction. Each one must carry the call line of its
// own arm.
//
// One of these two assertions fails in two cases. The first case is that both
// call sites share one record. The second is that either one reports the line
// of the other arm.
// CHECK: [[CALL_THEN:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[THEN_LINE]] [[MAIN]]
// CHECK: [[CALL_ELSE:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[ELSE_LINE]] [[MAIN]]

// In the scope of the caller, the shader loads `a` one time, with a real value,
// and computes the condition from it. The load sits outside the if statement,
// so both arms share it.
//
// Slang emits each DebugValue two times. This test asserts the first one
// only.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugFunctionDefinition [[MAIN]] %computeMain
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: [[IN:%[0-9]+]] = OpAccessChain {{.*}} %buffer0 %int_0 %int_0
// CHECK: [[VAL:%[0-9]+]] = OpLoad %uint [[IN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %a [[VAL]]
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
// On entry, the scope becomes Foo, under the DebugInlinedAt of this call. The
// line table must move at once to a line of Foo, which is the declaration line
// captured above. This move is what makes stepping into Foo appear to enter it.
//
// This test also captures the body statement line of Foo, with the lineEnd
// operand wildcarded, and requires it in full in the else arm below. The two
// inlined copies therefore assert against each other.
// CHECK: [[THEN_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL_THEN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_LINE]] [[FOO_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %x [[VAL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_BODY_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}}
// CHECK: [[THEN_RESULT:%[0-9]+]] = OpIMul %uint [[VAL]] %uint_2

// Execution leaves the inlined body. The scope returns to the caller, and the
// line table must return to the call statement of this arm. It must not return
// to the call statement of the other arm. That wrong line is the one way a
// shared inline record appears here. `b` then takes the value from the inlined
// copy.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[THEN_LINE]] [[THEN_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %b [[THEN_RESULT]]
// CHECK: [[OUT_THEN:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 %int_0
// CHECK: OpStore [[OUT_THEN]] [[THEN_RESULT]]

// This test asserts the else arm in the same way, against its own captures. The
// callee body line is now required in full, from the capture in the if arm.
// Both inlined copies must report the same line of Foo.
//
// [[ELSE_RESULT]] must be a different id from [[THEN_RESULT]]. That
// requirement is also the assertion that no pass merged the two inlined
// multiply instructions into one.
//
// The two instructions compute the same value from the same operand. A pass
// that hoists them, or that removes one as a common subexpression, leaves one
// copy. The line information of one arm only can then describe that copy.
//
// Slang computes the destination pointer before the addition here. The other
// two compilers use the opposite order.
// CHECK: [[ELSE_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL_ELSE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_LINE]] [[FOO_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %x [[VAL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_BODY_LINE]] [[FOO_BODY_LINE]]
// CHECK: [[ELSE_RESULT:%[0-9]+]] = OpIMul %uint [[VAL]] %uint_2
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[ELSE_LINE]] [[ELSE_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %c [[ELSE_RESULT]]
// CHECK: [[OUT_ELSE:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 %int_0
// CHECK: [[SUM:%[0-9]+]] = OpIAdd %uint [[ELSE_RESULT]] %uint_1
// CHECK: OpStore [[OUT_ELSE]] [[SUM]]

// After the if statement, the scope is back to the function of the caller.
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
    if (a > 10) {
        uint b = Foo(a);
        result[0] = b;
    } else {
        uint c = Foo(a);
        result[0] = c + 1;
    }
}
