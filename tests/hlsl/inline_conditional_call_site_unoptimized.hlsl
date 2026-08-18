// RUN: %dxc -T cs_6_0 -E computeMain -Od

// This test is the counterpart to inline_conditional_call_site.hlsl, with no
// inlining. The -Od flag disables the dxc optimizer. Foo therefore stays a real,
// separate function, and both call sites stay real OpFunctionCall
// instructions.
//
// This test is therefore the caller-side half of the same question. No compiler
// moves anything across a function boundary, so no inline record can be wrong.
// The debug information must still describe the conditional.
//
// Each arm of the if statement must have its own DebugLexicalBlock, nested in
// the body block of the caller. The local that each arm declares must be
// parented to the block of that arm, and each call must run under that block.
//
// The Scope operands of DebugInlinedAt in the optimized test must agree with
// this shape once dxc inlines Foo. If the arms have the wrong scope here, the
// inlined test cannot be correct either.
//
// This test identifies the arms with no absolute line numbers, in the same way
// as the optimized test. The if arm declares `b` only, and the else arm
// declares `c` only.
//
// dxc declares the else arm first. It also anchors the block of each arm at the
// keyword that opens the arm, which is `if` or `} else {`. It does not anchor
// the block at the first statement of the arm. This test therefore takes the
// call line from `b` or `c`, and not from the block.

// These assertions capture the name strings. dxc emits `c` before `b`.
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[X_NAME:%[0-9]+]] = OpString "x"
// CHECK: [[MAIN_NAME:%[0-9]+]] = OpString "computeMain"
// CHECK: [[C_NAME:%[0-9]+]] = OpString "c"
// CHECK: [[B_NAME:%[0-9]+]] = OpString "b"
// CHECK: [[A_NAME:%[0-9]+]] = OpString "a"

// These assertions cover the callee, the lexical block that dxc inserts for the
// body of the callee, and the parameter of the callee. Foo's declaration line is captured for the line table inside
// its own body far below.
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[FOO_LINE:%[a-zA-Z_0-9]+]] {{.*}}
// CHECK: [[FOO_BLOCK:%[0-9]+]] = OpExtInst {{.*}} DebugLexicalBlock {{.*}} [[FOO]]
// CHECK: [[X:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[X_NAME]] {{.*}} [[FOO]] {{.*}}

// These assertions cover the caller, and the lexical block for the body of the
// caller.
// CHECK: [[MAIN:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[MAIN_NAME]]
// CHECK: [[MAIN_BLOCK:%[0-9]+]] = OpExtInst {{.*}} DebugLexicalBlock {{.*}} [[MAIN]]

// These assertions cover the lexical block of the else arm, and the variable
// that identifies it.
//
// The shader declares `c` on the same statement as the call, so the Line operand
// of `c` is the call line. This test captures that line one time, as
// [[ELSE_LINE]], and reuses it below.
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

// The debug information does not describe the call as an inlined call.
//
// Keep this guard in place, between a declaration assertion and a body
// assertion. A CHECK-NOT directive searches only the span between the two
// matches around it. The compiler declares DebugInlinedAt in the module
// preamble. At the end of the file, this guard matches nothing and always
// passes.
// CHECK-NOT: {{DebugInlinedAt}}

// At -Od, dxc keeps its entry-point wrapper as a real function. That function
// calls the real body in src_computeMain.
//
// The scope of the caller is the body block. `a` is real Function-storage
// memory, and a DebugDeclare describes it and binds to that memory. The
// condition reloads it.
// CHECK: {{%[0-9]+}} = OpFunctionCall %void %src_computeMain {{%[a-zA-Z_0-9]+}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN_BLOCK]]
// CHECK: [[IN:%[0-9]+]] = OpAccessChain {{.*}} %buffer0 %int_0 %uint_0
// CHECK: [[VAL:%[0-9]+]] = OpLoad %uint [[IN]]
// CHECK: OpStore %a [[VAL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[A]] %a {{%[a-zA-Z_0-9]+}}
// CHECK: [[A_RELOAD:%[0-9]+]] = OpLoad %uint %a
// CHECK: [[COND:%[0-9]+]] = OpUGreaterThan %bool [[A_RELOAD]] %uint_10

// This test captures both target labels of the branch. Those captures pin every
// assertion below to the arm that it belongs to.
// CHECK: OpSelectionMerge [[MERGE_LABEL:%[a-zA-Z_0-9]+]] None
// CHECK: OpBranchConditional [[COND]] [[THEN_LABEL:%[a-zA-Z_0-9]+]] [[ELSE_LABEL:%[a-zA-Z_0-9]+]]

// This is the if arm. The scope must become the block of this arm, and must not
// stay on the body block of the caller. The line table must be on the call
// statement of this arm.
//
// The call passes the argument through a real argument slot. The call is a real
// OpFunctionCall, and the shader stores its result into `b`. A DebugDeclare
// describes `b` and binds it to that real memory.
// CHECK: [[THEN_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[THEN_BLOCK]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[THEN_LINE]] [[THEN_LINE]]
// CHECK: [[THEN_ARG:%[0-9]+]] = OpLoad %uint %a
// CHECK: OpStore %param_var_x [[THEN_ARG]]
// CHECK: [[THEN_RESULT:%[0-9]+]] = OpFunctionCall %uint %Foo %param_var_x
// CHECK: OpStore %b [[THEN_RESULT]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[B]] %b {{%[a-zA-Z_0-9]+}}
// CHECK: [[B_RELOAD:%[0-9]+]] = OpLoad %uint %b
// CHECK: [[OUT_THEN:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 %uint_0
// CHECK: OpStore [[OUT_THEN]] [[B_RELOAD]]

// This test asserts the else arm in the same way, against its own captures. The
// else arm has its own argument slot. The two call sites must not share one
// slot.
// CHECK: [[ELSE_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[ELSE_BLOCK]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[ELSE_LINE]] [[ELSE_LINE]]
// CHECK: [[ELSE_ARG:%[0-9]+]] = OpLoad %uint %a
// CHECK: OpStore %param_var_x_0 [[ELSE_ARG]]
// CHECK: [[ELSE_RESULT:%[0-9]+]] = OpFunctionCall %uint %Foo %param_var_x_0
// CHECK: OpStore %c [[ELSE_RESULT]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[C]] %c {{%[a-zA-Z_0-9]+}}
// CHECK: [[C_RELOAD:%[0-9]+]] = OpLoad %uint %c
// CHECK: [[SUM:%[0-9]+]] = OpIAdd %uint [[C_RELOAD]] %uint_1
// CHECK: [[OUT_ELSE:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 %uint_0
// CHECK: OpStore [[OUT_ELSE]] [[SUM]]

// After the if statement, the scope is back to the function of the caller. The
// block of neither arm reaches outside the conditional.
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
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO_BLOCK]]
// CHECK: [[X_VAL:%[0-9]+]] = OpLoad %uint %x
// CHECK: {{%[0-9]+}} = OpIMul %uint [[X_VAL]] %uint_2

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
