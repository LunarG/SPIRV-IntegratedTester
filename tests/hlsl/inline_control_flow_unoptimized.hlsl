// RUN: %dxc -T cs_6_0 -E computeMain -Od

// This shader is the same branchy shader as inline_control_flow.hlsl. This test
// turns off the dxc optimizations. Foo stays a real, separate function, and dxc
// does not inline it into computeMain.
//
// The two returns are on different source lines. They must stay on different
// lines, whether or not a compiler inlines Foo. This test asserts that with no
// absolute line numbers.
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[FOO_LINE:%[a-zA-Z_0-9]+]] {{.*}}
// CHECK: [[FOO_BLOCK:%[0-9]+]] = OpExtInst {{.*}} DebugLexicalBlock {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[FOO]]

// dxc anchors a lexical block at the keyword that opens it. The Line operand of
// this block is therefore the line of the `if` statement. It is not the line of
// the early return, which is the next line down.
//
// This test captures that line for two reasons. It gives the condition below a
// positive line to assert against, and it gives the fall-through return one
// more line that it must not report.
// CHECK: [[IF_BLOCK:%[0-9]+]] = OpExtInst {{.*}} DebugLexicalBlock {{%[a-zA-Z_0-9]+}} [[IF_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} [[FOO_BLOCK]]

// The debug information does not describe the call as an inlined call.
//
// Keep this guard in place, between a declaration assertion and a body
// assertion. A CHECK-NOT directive searches only the span between the two
// matches around it. The compiler declares DebugInlinedAt in the module
// preamble. At the end of the file, this guard matches nothing and always
// passes.
// CHECK-NOT: {{DebugInlinedAt}}

// The shader loads `a` from the buffer one time, into real memory. At -Od, dxc
// passes function arguments by pointer to real Function-storage memory.
//
// The call therefore reloads the real value of `a` and stores it into a real
// argument slot. It then calls Foo through that slot. The real value that Foo
// returns reaches result[0].
// CHECK: [[BUFVAL:%[0-9]+]] = OpLoad %uint
// CHECK: OpStore %a [[BUFVAL]]
// CHECK: [[A:%[0-9]+]] = OpLoad %uint %a
// CHECK: OpStore %param_var_x [[A]]
// CHECK: [[FOO_CALL:%[0-9]+]] = OpFunctionCall %uint %Foo %param_var_x
// CHECK: OpStore {{%[0-9]+}} [[FOO_CALL]]

// The parameter of Foo is real Function-storage memory. A DebugDeclare
// instruction describes it and binds to that memory. The body of Foo opens in
// the scope of Foo, on the declaration line of Foo.
// CHECK: %x = OpFunctionParameter {{.*}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_LINE]] [[FOO_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare {{%[a-zA-Z_0-9]+}} %x {{%[a-zA-Z_0-9]+}}

// The condition `x > 10` runs in the lexical block for the body of Foo, on the
// line of the `if` statement. The shader computes it from a real reload of the
// real parameter memory.
//
// The if statement has an early return and no else, so the false edge goes
// directly to the merge block. This test captures both targets, which pins the
// assertions for each branch to the branch that they belong to.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO_BLOCK]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[IF_LINE]] [[IF_LINE]]
// CHECK: [[COND_X:%[0-9]+]] = OpLoad %uint %x
// CHECK: [[COND:%[0-9]+]] = OpUGreaterThan %bool [[COND_X]]
// CHECK: OpSelectionMerge [[FALSE_LABEL:%[a-zA-Z_0-9]+]] None
// CHECK: OpBranchConditional [[COND]] [[TRUE_LABEL:%[a-zA-Z_0-9]+]] [[FALSE_LABEL]]

// The early-return branch (`return x * 2`) runs in the lexical block of the if
// statement. It carries its own DebugLine, which this test captures. dxc does
// not inline Foo, so its DebugScope has no DebugInlinedAt operand.
//
// At this optimization level, the early return stays a real early return. This
// branch returns directly out of Foo, with no merge block and no temporary.
// CHECK: [[TRUE_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[IF_BLOCK]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[TRUE_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}}
// CHECK: [[TRUE_X:%[0-9]+]] = OpLoad %uint %x
// CHECK: [[TRUE_RESULT:%[0-9]+]] = OpIMul %uint [[TRUE_X]]
// CHECK: OpReturnValue [[TRUE_RESULT]]

// The fall-through return (`return x + 1`) is back in the block for the body of
// Foo. Its DebugLine must report neither the line of the early return nor the
// line of the `if` statement. The two returns must not collapse onto one source
// line.
//
// This branch also returns its own real value directly out of Foo.
// CHECK: [[FALSE_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO_BLOCK]]
// CHECK-NOT: DebugLine {{%[a-zA-Z_0-9]+}} [[TRUE_LINE]] [[TRUE_LINE]]
// CHECK-NOT: DebugLine {{%[a-zA-Z_0-9]+}} [[IF_LINE]] [[IF_LINE]]
// CHECK: [[FALSE_X:%[0-9]+]] = OpLoad %uint %x
// CHECK: [[FALSE_RESULT:%[0-9]+]] = OpIAdd %uint [[FALSE_X]]
// CHECK: OpReturnValue [[FALSE_RESULT]]

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
