// RUN: %glslang

// This shader is a GLSL restatement of inline_control_flow_optimized.comp.glsl.
// The glslang default never inlines (see CLAUDE.md). Foo stays a real, separate
// function, and glslang does not inline it into main.
//
// The two returns are on different source lines. They must stay on different
// lines, whether or not a compiler inlines Foo. This test asserts that with no
// absolute line numbers.
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[FOO_LINE:%[a-zA-Z_0-9]+]] {{.*}}

// glslang anchors a lexical block at the first statement of that block. Inside
// the if statement of Foo, the first statement is the early return. The Line
// operand of this block is therefore the line of the early return, which makes
// it a positive anchor.
// CHECK: [[IF_BLOCK:%[0-9]+]] = OpExtInst {{.*}} DebugLexicalBlock {{%[a-zA-Z_0-9]+}} [[TRUE_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} [[FOO]]

// The debug information does not describe the call as an inlined call.
//
// Keep this guard in place, between a declaration assertion and a body
// assertion. A CHECK-NOT directive searches only the span between the two
// matches around it. The compiler declares DebugInlinedAt in the module
// preamble. At the end of the file, this guard matches nothing and always
// passes.
// CHECK-NOT: {{DebugInlinedAt}}

// The shader loads `a` from the buffer one time, into real memory. glslang
// passes function arguments by pointer to real Function-storage memory.
//
// The call therefore reloads the real value of `a` and stores it into a real
// argument slot. It then calls Foo through that slot. The real value that Foo
// returns reaches result[0].
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare {{%[a-zA-Z_0-9]+}} %a {{%[a-zA-Z_0-9]+}}
// CHECK: [[BUFVAL:%[0-9]+]] = OpLoad %uint
// CHECK: OpStore %a [[BUFVAL]]
// CHECK: [[A:%[0-9]+]] = OpLoad %uint %a
// CHECK: OpStore %param [[A]]
// CHECK: [[FOO_CALL:%[0-9]+]] = OpFunctionCall %uint %Foo_u1_ %param
// CHECK: OpStore {{%[0-9]+}} [[FOO_CALL]]

// The parameter of Foo is real Function-storage memory. A DebugDeclare
// instruction describes it and binds to that memory. The body of Foo opens in
// the scope of Foo, on the declaration line of Foo.
// CHECK: %x = OpFunctionParameter {{.*}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_LINE]] [[FOO_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare {{%[a-zA-Z_0-9]+}} %x {{%[a-zA-Z_0-9]+}}

// The shader computes the condition `x > 10` from a real reload of the real
// parameter memory.
//
// The if statement has an early return and no else, so the false edge goes
// directly to the merge block. This test captures both targets, which pins the
// assertions for each branch to the branch that they belong to.
// CHECK: [[COND_X:%[0-9]+]] = OpLoad %uint %x
// CHECK: [[COND:%[0-9]+]] = OpUGreaterThan %bool [[COND_X]]
// CHECK: OpSelectionMerge [[FALSE_LABEL:%[a-zA-Z_0-9]+]] None
// CHECK: OpBranchConditional [[COND]] [[TRUE_LABEL:%[a-zA-Z_0-9]+]] [[FALSE_LABEL]]

// The early-return branch (`return x * 2`) runs in the lexical block of the if
// statement. It reports the line that opened that block. glslang does not
// inline Foo, so its DebugScope has no DebugInlinedAt operand.
//
// At this optimization level, the early return stays a real early return. This
// branch returns directly out of Foo, with no merge block and no temporary.
// CHECK: [[TRUE_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[IF_BLOCK]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[TRUE_LINE]] [[TRUE_LINE]]
// CHECK: [[TRUE_X:%[0-9]+]] = OpLoad %uint %x
// CHECK: [[TRUE_RESULT:%[0-9]+]] = OpIMul %uint [[TRUE_X]]
// CHECK: OpReturnValue [[TRUE_RESULT]]

// The fall-through return (`return x + 1`) is back in the scope of Foo. Its
// DebugLine must report neither the line of the early return nor the
// declaration line of Foo. The two returns must not collapse onto one source
// line.
//
// This branch also returns its own real value directly out of Foo.
// CHECK: [[FALSE_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]]
// CHECK-NOT: DebugLine {{%[a-zA-Z_0-9]+}} [[TRUE_LINE]] [[TRUE_LINE]]
// CHECK-NOT: DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_LINE]] [[FOO_LINE]]
// CHECK: [[FALSE_X:%[0-9]+]] = OpLoad %uint %x
// CHECK: [[FALSE_RESULT:%[0-9]+]] = OpIAdd %uint [[FALSE_X]]
// CHECK: OpReturnValue [[FALSE_RESULT]]

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
