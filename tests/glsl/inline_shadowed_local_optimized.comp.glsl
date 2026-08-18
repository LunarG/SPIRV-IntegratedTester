// RUN: %glslang && %spirv_opt %spv -O -o %spv

// Foo declares a local named `scale`, and main declares one too. glslang
// inlines Foo into main, so both locals sit in the same function body at the
// same time. The debug information is then the only thing that can tell them
// apart.
//
// The name cannot tell them apart. The module holds one OpString "scale" only,
// and both variables share it. The identity of each variable lives in the
// Parent operand of its DebugLocalVariable.
//
// A regression can collapse the two variables into one, or reparent either one.
// No name-based assertion sees such a regression. This test exists to catch
// it.

// Both variables share one name string.
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[X_NAME:%[0-9]+]] = OpString "x"
// CHECK: [[SCALE_NAME:%[0-9]+]] = OpString "scale"

// glslang parents locals directly to the DebugFunction. This module has no
// DebugLexicalBlock level. dxc behaves differently.
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]]
// CHECK: [[X:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[X_NAME]]
// CHECK: [[MAIN:%[0-9]+]] = OpExtInst {{.*}} DebugFunction {{%[a-zA-Z_0-9]+}}

// The Parent operand is the one difference between the two shadowing
// variables. The variable of the callee comes first, parented to Foo. The
// variable of the caller comes second, parented to main. Both Name operands are
// the same OpString, captured above.
//
// This test captures the declaration line of the callee here, and compares it
// against the line table below. This test needs no absolute line numbers.
// CHECK: [[SCALE_CALLEE:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[SCALE_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[CALLEE_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} [[FOO]] {{.*}}
// CHECK: [[SCALE_CALLER:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[SCALE_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[MAIN]] {{.*}}
// CHECK: [[CALL:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALLER_LINE:%[a-zA-Z_0-9]+]] [[MAIN]]

// In the scope of the caller, the `scale` of the caller holds 3. The
// DebugValue binds to [[SCALE_CALLER]]. This binding is the proof that the
// value reached the variable of the caller, and not the one of the callee.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[SCALE_CALLER]] %uint_3

// The line table must be on the call site here. This test captured
// [[CALLER_LINE]] above, from DebugInlinedAt. This assertion therefore also
// compares the "inlined from" line against the line that the line table
// reports for the call statement.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALLER_LINE]] [[CALLER_LINE]]
// CHECK: [[IN:%[0-9]+]] = OpAccessChain
// CHECK: [[VAL:%[0-9]+]] = OpLoad %uint [[IN]]

// Execution enters the inlined body of Foo. The line table must enter the body
// of the callee, and must not stay on the call site. The line here is the line
// that declares the `scale` of the callee.
//
// If the inliner attributes the whole inlined body to the call site, stepping
// into Foo does not appear to enter it, and this assertion fails.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[X]] [[VAL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALLEE_LINE]] [[CALLEE_LINE]]

// The `scale` of the callee holds 5, and its real multiply uses that
// value.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[SCALE_CALLEE]] %uint_5
// CHECK: [[PRODUCT:%[0-9]+]] = OpIMul %uint [[VAL]] %uint_5

// Execution leaves the inlined body. The scope returns to the caller, and the
// line table returns to the statement line of the caller.
//
// The arithmetic after this point uses the 3 of the caller, and not the 5 of
// the callee. The two variables therefore stayed distinct across the whole
// inlined region.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALLER_LINE]] [[CALLER_LINE]]
// CHECK: [[SUM:%[0-9]+]] = OpIAdd %uint [[PRODUCT]] %uint_3
// CHECK: [[OUT:%[0-9]+]] = OpAccessChain
// CHECK: OpStore [[OUT]] [[SUM]]

#version 450
layout(set = 0, binding = 0, std430) readonly buffer Buffer0 { uint buffer0[]; };
layout(set = 0, binding = 1, std430) buffer Result { uint result[]; };

uint Foo(uint x) {
    uint scale = 5;
    return x * scale;
}

void main() {
    uint scale = 3;
    result[0] = Foo(buffer0[0]) + scale;
}
