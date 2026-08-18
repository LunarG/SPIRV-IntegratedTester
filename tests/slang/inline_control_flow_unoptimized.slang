// RUN: %slangc -O0

// This shader is the same branchy shader as inline_control_flow.slang. This
// test disables the Slang optimizer. Foo stays a real, separate function, and
// Slang does not inline it into computeMain.
//
// The two returns are on different source lines. They must stay on different
// lines, whether or not a compiler inlines Foo.
//
// Slang emits no DebugLexicalBlock at any optimization level, so no declaration
// anchors either return line. This test captures the line of the early return
// from its own DebugLine. The fall-through return must report neither that
// line, nor the line of the condition, nor the declaration line of Foo. This
// test uses no absolute line numbers.
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[FOO_LINE:%[a-zA-Z_0-9]+]] {{.*}}

// The debug information does not describe the call as an inlined call.
//
// Keep this guard in place, between a declaration assertion and a body
// assertion. A CHECK-NOT directive searches only the span between the two
// matches around it. The compiler declares DebugInlinedAt in the module
// preamble. At the end of the file, this guard matches nothing and always
// passes.
// CHECK-NOT: {{DebugInlinedAt}}

// computeMain calls Foo through a real function call, and passes the real value
// of `a`. The real value that Foo returns reaches result[0].
// CHECK: [[A:%[0-9]+]] = OpLoad %uint
// CHECK: [[FOO_CALL:%[0-9]+]] = OpFunctionCall %uint %Foo [[A]]
// CHECK: OpStore {{%[0-9]+}} [[FOO_CALL]]

// The parameter of Foo arrives by value, and Slang copies it into real
// Function-storage memory. A DebugDeclare binds its debug variable to that
// memory. The body of Foo opens in the scope of Foo, on the declaration line of
// Foo.
// CHECK: %x = OpFunctionParameter %uint
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugFunctionDefinition [[FOO]] %Foo
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_LINE]] [[FOO_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare %x_0 %_dbgvar_x {{%[a-zA-Z_0-9]+}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %x_0 %x
// CHECK: OpStore %_dbgvar_x %x

// The shader computes the condition `x > 10` from the real parameter, on its
// own line. This test captures that line, so that the fall-through return can
// be required not to report it either.
//
// The if statement has an early return and no else, so the false edge goes
// directly to the merge block. This test captures both targets, which pins the
// assertions for each branch to the branch that they belong to.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[COND_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}}
// CHECK: [[COND:%[0-9]+]] = OpUGreaterThan %bool %x
// CHECK: OpSelectionMerge [[FALSE_LABEL:%[a-zA-Z_0-9]+]] None
// CHECK: OpBranchConditional [[COND]] [[TRUE_LABEL:%[a-zA-Z_0-9]+]] [[FALSE_LABEL]]

// The early-return branch (`return x * 2`) carries its own DebugLine, which
// this test captures. Slang does not inline Foo, so its DebugScope names Foo
// with no DebugInlinedAt operand.
//
// At this optimization level, the early return stays a real early return. This
// branch returns directly out of Foo, with no merge block and no temporary.
// CHECK: [[TRUE_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[TRUE_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}}
// CHECK: [[TRUE_RESULT:%[0-9]+]] = OpIMul %uint %x
// CHECK: OpReturnValue [[TRUE_RESULT]]

// The fall-through return (`return x + 1`) must report a line of its own. That
// line must not be the line of the early return, because the two returns must
// not collapse onto one source line. It must not be the line of the condition,
// and it must not be the declaration line of Foo.
//
// This branch also returns its own real value directly out of Foo.
// CHECK: [[FALSE_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]]
// CHECK-NOT: DebugLine {{%[a-zA-Z_0-9]+}} [[TRUE_LINE]] [[TRUE_LINE]]
// CHECK-NOT: DebugLine {{%[a-zA-Z_0-9]+}} [[COND_LINE]] [[COND_LINE]]
// CHECK-NOT: DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_LINE]] [[FOO_LINE]]
// CHECK: [[FALSE_RESULT:%[0-9]+]] = OpIAdd %uint %x
// CHECK: OpReturnValue [[FALSE_RESULT]]

StructuredBuffer<uint> buffer0;
RWStructuredBuffer<uint> result;

uint Foo(uint x) {
    if (x > 10) {
        return x * 2;
    }
    return x + 1;
}

[shader("compute")]
[numthreads(1,1,1)]
void computeMain(uint3 threadId : SV_DispatchThreadID)
{
    uint a = buffer0[0];
    result[0] = Foo(a);
}
