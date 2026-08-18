// RUN: %glslang && %spirv_opt %spv -O -o %spv

// This shader is a GLSL restatement of inline_control_flow.slang. Foo holds
// control flow: an early return, and a second return after the if statement.
//
// The glslang default never inlines (see CLAUDE.md). This test therefore adds a
// general SPIR-V optimizer pass, which splices the branchy body of Foo into the
// body of main.
//
// A DebugFunction must still describe Foo, and a DebugInlinedAt must describe
// the call site.
//
// The two returns are on different source lines, and they must stay on
// different lines. That requirement is the purpose of this test. A debugger
// that steps through Foo must be able to tell which return it is on. This test
// asserts that with no absolute line numbers.
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]]

// glslang anchors a lexical block at the first statement of that block. Inside
// the if statement of Foo, the first statement is the early return. The Line
// operand of this block is therefore the line of the early return, which makes
// it a positive anchor.
//
// On this compiler, the test can require the line of the early return to be one
// known line. On the other compilers, it can require only that the line differs
// from the other one.
// CHECK: [[IF_BLOCK:%[0-9]+]] = OpExtInst {{.*}} DebugLexicalBlock {{%[a-zA-Z_0-9]+}} [[TRUE_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} [[FOO]]
// CHECK: [[CALL:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALL_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}}

// The shader loads `a` one time, with a real value, in the scope of the
// caller.
// CHECK: [[A:%[0-9]+]] = OpLoad %uint
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue {{%[a-zA-Z_0-9]+}} [[A]]

// Execution enters the inlined body of Foo. The scope becomes Foo, under the
// DebugInlinedAt of this call, and the parameter of Foo takes the loaded value.
// The line at this point is still the line of the call statement.
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
// CHECK: OpSelectionMerge [[FALSE_LABEL:%[a-zA-Z_0-9]+]] None
// CHECK: OpBranchConditional [[COND]] [[TRUE_LABEL:%[a-zA-Z_0-9]+]] [[FALSE_LABEL]]

// The early-return branch (`return x * 2`) runs in the lexical block of the if
// statement, bound to the DebugInlinedAt of this call. It reports the line that
// opened that block.
// CHECK: [[TRUE_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[IF_BLOCK]] [[CALL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[TRUE_LINE]] [[TRUE_LINE]]
// CHECK: [[TRUE_RESULT:%[0-9]+]] = OpIMul %uint [[A]]

// The fall-through return (`return x + 1`) is back in the scope of Foo, bound
// to the DebugInlinedAt of this same call.
//
// Its DebugLine must report neither the line of the early return nor the line
// of the call site. The two returns must not collapse onto one source line.
//
// No declaration anchors the line of the fall-through return. This test
// therefore states the requirement as those two inequalities.
// CHECK: [[FALSE_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL]]
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

#version 450
layout(set = 0, binding = 0, std430) readonly buffer Buffer0 { uint buffer0[]; };
layout(set = 0, binding = 1, std430) buffer Result { uint result[]; };

uint Foo(uint x) {
    if (x > 10) {
        return x * 2;
    }
    return x + 1;
}

void main() {
    uint a = buffer0[0];
    result[0] = Foo(a);
}
