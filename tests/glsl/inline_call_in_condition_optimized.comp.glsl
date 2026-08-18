// RUN: %glslang && %spirv_opt %spv -O -o %spv

// The shader calls Foo from the condition of an if statement, and not from
// either arm.
//
// This test is the companion to
// inline_conditional_call_site_optimized.comp.glsl, and its mirror image. In
// that test, the call sits inside an arm, and its inlined body must be scoped
// to that arm. In this test, the shader evaluates the call before the branch
// exists.
//
// The inlined body therefore lands in the header block, above
// OpSelectionMerge, and it runs on every path.
//
// The DebugInlinedAt of the call must name the enclosing scope, which is main.
// It must not name the DebugLexicalBlock of either arm, because the header
// block is not inside either arm.
//
// A compiler can scope a condition-expression call to one of the arms. Such a
// compiler tells a debugger that the call happened inside a branch that
// execution can skip.
//
// Both arms declare a local, `b` or `c`, for one purpose: to make their
// lexical blocks identifiable by name. This test captures each block as the
// Parent of its own variable, and each block is a distinct instruction from the
// DebugFunction of main. The requirement that the Scope of the call be
// [[MAIN]] is therefore the statement that the Scope is neither arm.
//
// The call sits in the condition only. A second call inside an arm, with the
// same argument, does not survive. The header block dominates both arms, so
// spirv-opt merges the two inlined copies as a common subexpression. One
// DebugInlinedAt then remains, attributed to the condition.
//
// The question of which call line survives such a merge deserves a test of its
// own. It has no place here, because it obscures the scoping question.

// These assertions capture the name strings.
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[X_NAME:%[0-9]+]] = OpString "x"
// CHECK: [[MAIN_NAME:%[0-9]+]] = OpString "main"
// CHECK: [[A_NAME:%[0-9]+]] = OpString "a"
// CHECK: [[B_NAME:%[0-9]+]] = OpString "b"
// CHECK: [[C_NAME:%[0-9]+]] = OpString "c"

// These assertions cover the callee, its parameter, the caller, and `a` in the
// caller.
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]]
// CHECK: [[X:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[X_NAME]] {{.*}} [[FOO]] {{.*}}
// CHECK: [[MAIN:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[MAIN_NAME]]
// CHECK: [[A:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[A_NAME]] {{.*}} [[MAIN]] {{.*}}

// These assertions cover the lexical block of each arm. The local that only
// that arm declares identifies each block, and each block is parented to main.
// This test captures both, so that the Scope of the call can be required to be
// neither of them.
// CHECK: [[THEN_BLOCK:%[0-9]+]] = OpExtInst {{.*}} DebugLexicalBlock {{%[a-zA-Z_0-9]+}} [[THEN_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} [[MAIN]]
// CHECK: [[B:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[B_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[THEN_LINE]] {{%[a-zA-Z_0-9]+}} [[THEN_BLOCK]] {{.*}}
// CHECK: [[ELSE_BLOCK:%[0-9]+]] = OpExtInst {{.*}} DebugLexicalBlock {{%[a-zA-Z_0-9]+}} [[ELSE_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} [[MAIN]]
// CHECK: [[C:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[C_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[ELSE_LINE]] {{%[a-zA-Z_0-9]+}} [[ELSE_BLOCK]] {{.*}}

// This assertion is the heart of this test. There is one call site, so there is
// one DebugInlinedAt. Its Scope operand is main itself. It is not
// [[THEN_BLOCK]], and it is not [[ELSE_BLOCK]].
//
// The Line operand is the line of the condition. This test captures it here,
// and compares it against the line table below.
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
// value.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: [[IN:%[0-9]+]] = OpAccessChain {{.*}} %int_0 %int_0
// CHECK: [[VAL:%[0-9]+]] = OpLoad %uint [[IN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[A]] [[VAL]]

// The inlined body of Foo sits in the header block. Every assertion from here
// to the OpBranchConditional below comes before the branch.
//
// That order is the proof that no pass sank the body into an arm. The body also
// sits above OpSelectionMerge, which is the proof that it runs on every path.
//
// On entry, the line table is on the condition, and the parameter of Foo takes
// the loaded value. The line table must then leave the line of the condition.
//
// glslang reports the body statement of Foo, and not its declaration, so no
// declaration anchors that line. This test has one inlined copy, so no second
// copy exists to compare against. The requirement is therefore a CHECK-NOT
// guard over the region up to the multiply.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[X]] [[VAL]]
// CHECK-NOT: DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: [[FOO_RESULT:%[0-9]+]] = OpIMul %uint [[VAL]] %uint_2

// Execution leaves the inlined body. The scope returns to main, and the line
// table returns to the condition. The condition tests the value that Foo
// produced.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: [[COND:%[0-9]+]] = OpUGreaterThan %bool [[FOO_RESULT]] %uint_10

// The branch appears only at this point.
// CHECK: OpSelectionMerge [[MERGE_LABEL:%[a-zA-Z_0-9]+]] None
// CHECK: OpBranchConditional [[COND]] [[THEN_LABEL:%[a-zA-Z_0-9]+]] [[ELSE_LABEL:%[a-zA-Z_0-9]+]]

// Each arm enters its own lexical block, and computes its own value from the
// same loaded `a`. Neither arm holds any part of Foo. The condition above
// consumed the callee in full.
// CHECK: [[THEN_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[THEN_BLOCK]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[THEN_LINE]] [[THEN_LINE]]
// CHECK: [[B_VAL:%[0-9]+]] = OpIMul %uint [[VAL]] %uint_3
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[B]] [[B_VAL]]
// CHECK: [[OUT_THEN:%[0-9]+]] = OpAccessChain {{.*}} %int_0 %int_0
// CHECK: OpStore [[OUT_THEN]] [[B_VAL]]

// CHECK: [[ELSE_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[ELSE_BLOCK]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[ELSE_LINE]] [[ELSE_LINE]]
// CHECK: [[C_VAL:%[0-9]+]] = OpIAdd %uint [[VAL]] %uint_1
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[C]] [[C_VAL]]
// CHECK: [[OUT_ELSE:%[0-9]+]] = OpAccessChain {{.*}} %int_0 %int_0
// CHECK: OpStore [[OUT_ELSE]] [[C_VAL]]

// After the if statement, the scope is back to main.
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
    if (Foo(a) > 10) {
        uint b = a * 3;
        result[0] = b;
    } else {
        uint c = a + 1;
        result[0] = c;
    }
}
