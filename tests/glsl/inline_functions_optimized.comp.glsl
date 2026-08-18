// RUN: %glslang && %spirv_opt %spv -O -o %spv

// This shader is a GLSL restatement of the "Inline Functions" checklist item
// of issue #9: https://godbolt.org/z/hbzq4zz71
//
// The glslang default never inlines (see CLAUDE.md). This test therefore adds
// a general SPIR-V optimizer pass, which does inline Foo into main.
//
// A DebugFunction must still describe Foo, and another must describe main.
// This test finds them by name, and not by position. The contract does not fix
// which one glslang or spirv-opt emits first.
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[MAIN_NAME:%[0-9]+]] = OpString "main"
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]]
// CHECK: [[MAIN:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[MAIN_NAME]]

// The call `Foo(a)` and the call `Foo(a + 1)` are two separate call sites. A
// DebugInlinedAt instruction must describe each call site, and tie it back to
// main. The compiler must never merge the two calls into one.
//
// This test captures the Line operand of each DebugInlinedAt. A debugger
// reports this line as the "inlined from" position in a call stack, so the two
// lines must differ. Each line must also match the line that the line table
// reports for its own call statement. The assertions below compare both.
// CHECK: [[CALL1:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALL1_LINE:%[a-zA-Z_0-9]+]] [[MAIN]]
// CHECK: [[CALL2:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALL2_LINE:%[a-zA-Z_0-9]+]] [[MAIN]]

// The shader loads `a` one time, with a real value.
// CHECK: [[A:%[0-9]+]] = OpLoad %uint

// The inlined body of Foo for the first call, `Foo(a)`, runs under a
// DebugScope. That scope names Foo and the DebugInlinedAt of the first call.
// The parameter of Foo must track the real value of `a`, and not a
// placeholder.
//
// The line table enters the scope of Foo on the call statement, because the
// shader evaluates the argument there. The line table then moves to the body
// line of Foo, captured here as [[FOO_BODY_LINE]].
//
// glslang reports the body statement, and not the declaration line of Foo.
// Slang behaves differently. This test therefore cannot compare the captured
// line against the DebugFunction of Foo. Instead, the second inlined copy
// below reuses this line, where the surrounding call line differs.
//
// An inliner can attribute each inlined body to its own call site. Such an
// inliner binds this line to the first call, and the second copy then does not
// match.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL1]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL1_LINE]] [[CALL1_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[PARAM:%[a-zA-Z_0-9]+]] [[A]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_BODY_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}}
// CHECK: [[RESULT1:%[0-9]+]] = OpIMul %uint [[A]]

// After Foo returns from the first call, execution leaves the DebugScope of
// Foo and enters the DebugScope of main. The line table returns to the first
// call statement, and the computed result reaches result[0].
// CHECK-NOT: DebugScope [[FOO]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL1_LINE]] [[CALL1_LINE]]
// CHECK: OpStore {{%[0-9]+}} [[RESULT1]]

// The line table advances to the second call statement, which is a different
// line from the first. The shader then computes `a + 1` one time, with a real
// value.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL2_LINE]] [[CALL2_LINE]]
// CHECK: [[A_PLUS_1:%[0-9]+]] = OpIAdd %uint [[A]]

// The inlined body of Foo for the second call, `Foo(a + 1)`, runs under a
// DebugScope. That scope names Foo and the DebugInlinedAt of the second call,
// which differs from the first. The parameter of Foo must track the real value
// of `a + 1`. It must not track the value of the first call, and it must not be
// a placeholder. The body line must be the same line that Foo reported in the
// first copy.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL2]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[PARAM]] [[A_PLUS_1]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_BODY_LINE]] [[FOO_BODY_LINE]]
// CHECK: [[RESULT2:%[0-9]+]] = OpIMul %uint [[A_PLUS_1]]

// After Foo returns from the second call, execution leaves the DebugScope of
// Foo and enters the DebugScope of main again. The line table returns to the
// second call statement, and the computed result reaches result[1].
// CHECK-NOT: DebugScope [[FOO]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL2_LINE]] [[CALL2_LINE]]
// CHECK: OpStore {{%[0-9]+}} [[RESULT2]]

#version 450
layout(set = 0, binding = 0, std430) readonly buffer Buffer0 { uint buffer0[]; };
layout(set = 0, binding = 1, std430) buffer Result { uint result[]; };

uint Foo(uint x) {
    return x * 2;
}

void main() {
    uint a = buffer0[0];
    result[0] = Foo(a);
    result[1] = Foo(a + 1);
}
