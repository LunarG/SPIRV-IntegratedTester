// RUN: %glslang && %spirv_opt %spv -O -o %spv

// This shader is a GLSL restatement of nested_inline_functions.slang. main
// calls Bar, and Bar calls Foo.
//
// The glslang default never inlines (see CLAUDE.md). This test therefore adds
// a general SPIR-V optimizer pass, which does inline both calls. A
// DebugFunction must still describe each of the three functions. This test
// finds them by name.
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[BAR_NAME:%[0-9]+]] = OpString "Bar"
// CHECK: [[MAIN_NAME:%[0-9]+]] = OpString "main"
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]]
// CHECK: [[BAR:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[BAR_NAME]]
// CHECK: [[MAIN:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[MAIN_NAME]]

// The call site of Bar (`Bar(a)`, inside main) has its own DebugInlinedAt,
// tied back to main.
//
// The call site of Foo (`Foo(y)`, inside Bar) has its own DebugInlinedAt, tied
// to Bar. Its Inlined operand is the DebugInlinedAt of Bar, and not the one of
// main. This operand is what makes the chain describe a real two-level call
// stack, and not two independent, flat calls.
//
// This test captures the Line operand of each DebugInlinedAt. A debugger
// reports this line as the "inlined from" position for that frame of the call
// stack. The two lines must differ. Each line must also match the line that
// the line table reports for its own call statement, compared below.
// CHECK: [[CALL_BAR:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALL_BAR_LINE:%[a-zA-Z_0-9]+]] [[MAIN]]
// CHECK: [[CALL_FOO:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALL_FOO_LINE:%[a-zA-Z_0-9]+]] [[BAR]] [[CALL_BAR]]

// The shader loads `a` one time, with a real value.
// CHECK: [[A:%[0-9]+]] = OpLoad %uint

// The inlined body of Bar runs under a DebugScope. That scope names Bar and
// the DebugInlinedAt of Bar. The parameter of Bar must track the real value of
// `a`. On entry, the line table is on the call statement of main, where the
// shader evaluates the argument.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[BAR]] [[CALL_BAR]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_BAR_LINE]] [[CALL_BAR_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue {{%[a-zA-Z_0-9]+}} [[A]]

// The inlined body of Foo sits inside the body of Bar. It runs under a
// DebugScope that names Foo and the DebugInlinedAt of Foo, and not the one of
// Bar. The parameter of Foo must also track the real value of `a`, carried
// through Bar. On entry, the line table is on the call statement of Bar.
//
// At the arithmetic of Foo, the line table must have left that call line and
// moved to a line of Foo. This move is what makes stepping into Foo appear to
// enter it.
//
// glslang reports the body statement of Foo, and not its declaration line.
// This test inlines Foo one time only, so no second copy exists to compare
// against. The requirement is therefore a CHECK-NOT guard over the region up
// to the multiply. If an inliner attributes the whole body of Foo to the call
// site, the call line stays in force here and the guard fails.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL_FOO]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_FOO_LINE]] [[CALL_FOO_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue {{%[a-zA-Z_0-9]+}} [[A]]
// CHECK-NOT: DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_FOO_LINE]] [[CALL_FOO_LINE]]
// CHECK: [[FOO_RESULT:%[0-9]+]] = OpIMul %uint [[A]]

// After Foo returns, execution returns to the DebugScope of Bar. The line
// table returns to the statement of Bar, which is the line that called Foo.
// The computed result of Foo then feeds the computation of Bar.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[BAR]] [[CALL_BAR]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_FOO_LINE]] [[CALL_FOO_LINE]]
// CHECK: [[BAR_RESULT:%[0-9]+]] = OpIAdd %uint [[FOO_RESULT]]

// After Bar returns, execution returns to the DebugScope of main. The line
// table returns to the call statement of main, and the computed result reaches
// result[0].
//
// With the assertions above, this is the full two-level walk:
// main -> Bar -> Foo -> Bar -> main.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_BAR_LINE]] [[CALL_BAR_LINE]]
// CHECK: OpStore {{%[0-9]+}} [[BAR_RESULT]]

#version 450
layout(set = 0, binding = 0, std430) readonly buffer Buffer0 { uint buffer0[]; };
layout(set = 0, binding = 1, std430) buffer Result { uint result[]; };

uint Foo(uint x) {
    return x * 2;
}

uint Bar(uint y) {
    return Foo(y) + 1;
}

void main() {
    uint a = buffer0[0];
    result[0] = Bar(a);
}
