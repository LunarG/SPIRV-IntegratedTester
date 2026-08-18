// RUN: %glslang

// This test is the counterpart to
// inline_conditional_call_site_optimized.comp.glsl, with no inlining. The
// glslang default never inlines (see CLAUDE.md). Foo therefore stays a real,
// separate function, and both call sites stay real OpFunctionCall
// instructions.
//
// This test is therefore the caller-side half of the same question. No compiler
// moves anything across a function boundary, so no inline record can be wrong.
// The debug information must still describe the conditional.
//
// Each arm of the if statement must have its own DebugLexicalBlock, nested in
// main. The local that each arm declares must be parented to the block of that
// arm, and each call must run under that block.
//
// The Scope operands of DebugInlinedAt in the optimized test must agree with
// this shape once a compiler inlines Foo. If the arms have the wrong scope
// here, the inlined test cannot be correct either.
//
// This test identifies the arms with no absolute line numbers, in the same way
// as the optimized test. The if arm declares `b` only, and the else arm
// declares `c` only.

// These assertions capture the name strings.
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[X_NAME:%[0-9]+]] = OpString "x"
// CHECK: [[MAIN_NAME:%[0-9]+]] = OpString "main"
// CHECK: [[A_NAME:%[0-9]+]] = OpString "a"
// CHECK: [[B_NAME:%[0-9]+]] = OpString "b"
// CHECK: [[C_NAME:%[0-9]+]] = OpString "c"

// These assertions cover four items: the callee, its parameter, the caller, and
// `a` in the caller. None of the four sits inside a conditional, so all four
// are parented to a DebugFunction.
//
// This test captures the declaration line of Foo, for the line table inside the
// body of Foo far below.
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[FOO_LINE:%[a-zA-Z_0-9]+]] {{.*}}
// CHECK: [[X:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[X_NAME]] {{.*}} [[FOO]] {{.*}}
// CHECK: [[MAIN:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[MAIN_NAME]]
// CHECK: [[A:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[A_NAME]] {{.*}} [[MAIN]] {{.*}}

// These assertions cover the lexical block of the if arm, and the variable that
// identifies it.
//
// The shader declares `b` on the same statement as the call, so the Line operand
// of the block is also the call line. This test captures that line one time, as
// [[THEN_LINE]], and reuses it below.
//
// The Parent of the block must be the DebugFunction of the caller. The arm is a
// scope nested in main, and not a scope of its own.
// CHECK: [[THEN_BLOCK:%[0-9]+]] = OpExtInst {{.*}} DebugLexicalBlock {{%[a-zA-Z_0-9]+}} [[THEN_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} [[MAIN]]
// CHECK: [[B:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[B_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[THEN_LINE]] {{%[a-zA-Z_0-9]+}} [[THEN_BLOCK]] {{.*}}

// This assertion covers the lexical block of the else arm, identified in the
// same way by `c`.
// CHECK: [[ELSE_BLOCK:%[0-9]+]] = OpExtInst {{.*}} DebugLexicalBlock {{%[a-zA-Z_0-9]+}} [[ELSE_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} [[MAIN]]
// CHECK: [[C:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[C_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[ELSE_LINE]] {{%[a-zA-Z_0-9]+}} [[ELSE_BLOCK]] {{.*}}

// The debug information does not describe the call as an inlined call.
//
// Keep this guard in place, between a declaration assertion and a body
// assertion. A CHECK-NOT directive searches only the span between the two
// matches around it. The compiler declares DebugInlinedAt in the module
// preamble. At the end of the file, this guard matches nothing and always
// passes.
// CHECK-NOT: {{DebugInlinedAt}}

// In the scope of the caller, `a` is real Function-storage memory. A
// DebugDeclare describes it and binds to that memory. The shader stores the
// value from the buffer into that memory, and the condition then reloads it.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[A]] %a {{%[a-zA-Z_0-9]+}}
// CHECK: [[IN:%[0-9]+]] = OpAccessChain {{.*}} %int_0 %int_0
// CHECK: [[VAL:%[0-9]+]] = OpLoad %uint [[IN]]
// CHECK: OpStore %a [[VAL]]
// CHECK: [[A_RELOAD:%[0-9]+]] = OpLoad %uint %a
// CHECK: [[COND:%[0-9]+]] = OpUGreaterThan %bool [[A_RELOAD]] %uint_10

// This test captures both target labels of the branch. Those captures pin every
// assertion below to the arm that it belongs to.
// CHECK: OpSelectionMerge [[MERGE_LABEL:%[a-zA-Z_0-9]+]] None
// CHECK: OpBranchConditional [[COND]] [[THEN_LABEL:%[a-zA-Z_0-9]+]] [[ELSE_LABEL:%[a-zA-Z_0-9]+]]

// This is the if arm. The scope must become the block of this arm, and must not
// stay on main. The line table must be on the call statement of this arm.
//
// `b` is real memory, declared inside the arm. The call passes the argument
// through a real argument slot. The call is a real OpFunctionCall, and the
// shader stores its result into `b`.
// CHECK: [[THEN_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[THEN_BLOCK]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[THEN_LINE]] [[THEN_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[B]] %b {{%[a-zA-Z_0-9]+}}
// CHECK: [[THEN_ARG:%[0-9]+]] = OpLoad %uint %a
// CHECK: OpStore %param [[THEN_ARG]]
// CHECK: [[THEN_RESULT:%[0-9]+]] = OpFunctionCall %uint %Foo_u1_ %param
// CHECK: OpStore %b [[THEN_RESULT]]
// CHECK: [[B_RELOAD:%[0-9]+]] = OpLoad %uint %b
// CHECK: [[OUT_THEN:%[0-9]+]] = OpAccessChain {{.*}} %int_0 %int_0
// CHECK: OpStore [[OUT_THEN]] [[B_RELOAD]]

// This test asserts the else arm in the same way, against its own captures. The
// else arm has its own argument slot. The two call sites must not share one
// slot.
// CHECK: [[ELSE_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[ELSE_BLOCK]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[ELSE_LINE]] [[ELSE_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[C]] %c {{%[a-zA-Z_0-9]+}}
// CHECK: [[ELSE_ARG:%[0-9]+]] = OpLoad %uint %a
// CHECK: OpStore %param_0 [[ELSE_ARG]]
// CHECK: [[ELSE_RESULT:%[0-9]+]] = OpFunctionCall %uint %Foo_u1_ %param_0
// CHECK: OpStore %c [[ELSE_RESULT]]
// CHECK: [[C_RELOAD:%[0-9]+]] = OpLoad %uint %c
// CHECK: [[SUM:%[0-9]+]] = OpIAdd %uint [[C_RELOAD]] %uint_1
// CHECK: [[OUT_ELSE:%[0-9]+]] = OpAccessChain {{.*}} %int_0 %int_0
// CHECK: OpStore [[OUT_ELSE]] [[SUM]]

// After the if statement, the scope is back to main. The block of neither arm
// reaches outside the conditional.
// CHECK: [[MERGE_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]

// Foo is still a real, separate function with its own scope. Those two calls
// are the only way to reach it. Its parameter is real memory, and a
// DebugDeclare describes it and binds to that memory. The arithmetic of Foo
// reads that real memory.
// CHECK: %x = OpFunctionParameter {{.*}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_LINE]] [[FOO_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[X]] %x {{%[a-zA-Z_0-9]+}}
// CHECK: [[X_VAL:%[0-9]+]] = OpLoad %uint %x
// CHECK: {{%[0-9]+}} = OpIMul %uint [[X_VAL]] %uint_2

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
