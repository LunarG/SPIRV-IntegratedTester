// RUN: %dxc -T cs_6_0 -E computeMain

// This shader is the HLSL restatement of inline_control_flow.slang. Foo holds
// control flow: an early return, and a second return after the if statement.
//
// dxc inlines Foo into computeMain by default, so it splices this branchy body
// into the body of computeMain. A DebugFunction must still describe Foo.
//
// dxc emits an internal top-level wrapper DebugInlinedAt, which has no Inlined
// operand of its own. The assertion below steps past that wrapper, to reach the
// one for this call site.
//
// The two returns are on different source lines, and they must stay on
// different lines. That requirement is the purpose of this test. A debugger
// that steps through Foo must be able to tell which return it is on.
//
// This test asserts that with no absolute line numbers. It captures the line of
// the call site and the line of the early return. The fall-through return must
// report neither line.
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugInlinedAt {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}}
// CHECK: [[CALL:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALL_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}}

// The shader loads `a` one time, with a real value, in the scope of the
// caller.
// CHECK: [[A:%[0-9]+]] = OpLoad %uint
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue {{%[a-zA-Z_0-9]+}} [[A]]

// Execution enters the inlined body of Foo. The scope becomes Foo, under the
// DebugInlinedAt of this call, and the parameter of Foo takes the loaded value.
//
// dxc reports the line of the call statement at this point. The captured
// [[CALL_LINE]] must therefore be that line here.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue {{%[a-zA-Z_0-9]+}} [[A]]

// At the condition of Foo, the line table must have left the call statement and
// moved to a line of Foo. This move is what makes stepping into Foo appear to
// enter it.
// CHECK-NOT: DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: [[COND:%[0-9]+]] = OpUGreaterThan %bool [[A]]

// The if statement has an early return and no else, so the false edge goes
// directly to the merge block. This test captures both targets, which pins the
// assertions for each branch to the branch that they belong to.
//
// dxc emits more than one DebugScope for each branch. With a DebugScope anchor
// alone, the assertions for the fall-through can match instructions that are
// still inside the early-return block.
// CHECK: OpSelectionMerge [[FALSE_LABEL:%[a-zA-Z_0-9]+]] None
// CHECK: OpBranchConditional [[COND]] [[TRUE_LABEL:%[a-zA-Z_0-9]+]] [[FALSE_LABEL]]

// The early-return branch (`return x * 2`) must carry its own DebugLine, which
// this test captures. It must also run under a DebugScope that binds to the
// DebugInlinedAt of this call.
//
// dxc can name Foo itself as that scope, or a lexical block inside Foo. This
// choice is internal to dxc, so this test pins the DebugInlinedAt only.
//
// The capture wildcards the lineEnd operand, because effcee cannot define and
// use a variable on the same line. The guard below requires both operands to be
// this line.
// CHECK: [[TRUE_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope {{%[a-zA-Z_0-9]+}} [[CALL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[TRUE_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}}
// CHECK: [[TRUE_RESULT:%[0-9]+]] = OpIMul %uint [[A]]

// The fall-through return (`return x + 1`) must also run under a DebugScope
// that binds to the DebugInlinedAt of this same call.
//
// Its own DebugLine must report neither the line of the early return nor the
// line of the call site. The two returns must not collapse onto one source
// line.
// CHECK: [[FALSE_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope {{%[a-zA-Z_0-9]+}} [[CALL]]
// CHECK-NOT: DebugLine {{%[a-zA-Z_0-9]+}} [[TRUE_LINE]] [[TRUE_LINE]]
// CHECK-NOT: DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: [[FALSE_RESULT:%[0-9]+]] = OpIAdd %uint [[A]]

// The real value of the branch that ran reaches result[0]. An OpPhi merges the
// two returns. Its operands are the two real values, one for each branch, and
// each value is paired with the block that it came from.
//
// The merge therefore cannot take either value from the wrong branch. At this
// point, the line table is back on the call statement.
// CHECK: [[MERGED:%[0-9]+]] = OpPhi %uint [[TRUE_RESULT]] [[TRUE_LABEL]] [[FALSE_RESULT]] [[FALSE_LABEL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: OpStore {{%[0-9]+}} [[MERGED]]

StructuredBuffer<uint> buffer0;
RWStructuredBuffer<uint> result;

uint Foo(uint x) {
    if (x > 10) {
        return x * 2;
    }
    return x + 1;
}

[numthreads(1,1,1)]
void computeMain(uint3 threadId : SV_DispatchThreadID)
{
    uint a = buffer0[0];
    result[0] = Foo(a);
}
