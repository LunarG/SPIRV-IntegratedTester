// RUN: %slangc

// This shader is the "Inline Functions" checklist item of issue #9:
// https://godbolt.org/z/hbzq4zz71
//
// Slang inlines Foo into computeMain by default. A DebugFunction must still
// describe Foo, and another must describe computeMain. This test finds them by
// name, and not by position. The contract does not fix which one Slang emits
// first.
// CHECK: [[MAIN_NAME:%[0-9]+]] = OpString "computeMain"
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[MAIN:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[MAIN_NAME]]
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[FOO_LINE:%[a-zA-Z_0-9]+]] {{.*}}

// The call `Foo(a)` and the call `Foo(a + 1)` are two separate call sites. A
// DebugInlinedAt instruction must describe each call site, and tie it back to
// computeMain. The compiler must never merge the two calls into one.
//
// This test captures the Line operand of each DebugInlinedAt. A debugger
// reports this line as the "inlined from" position in a call stack, so the two
// lines must differ. Each line must also match the line that the line table
// reports for its own call statement. The assertions below compare both.
// CHECK: [[CALL1:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALL1_LINE:%[a-zA-Z_0-9]+]] [[MAIN]]
// CHECK: [[CALL2:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALL2_LINE:%[a-zA-Z_0-9]+]] [[MAIN]]

// The shader loads `a` one time, with a real value. The line table then moves
// to the first call statement.
// CHECK: [[A:%[0-9]+]] = OpLoad %uint
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL1_LINE]] [[CALL1_LINE]]

// The inlined body of Foo for the first call, `Foo(a)`, runs under a
// DebugScope. That scope names Foo and the DebugInlinedAt of the first call.
// The parameter of Foo must track the real value of `a`, and not a
// placeholder.
//
// The line table must enter the inlined body of Foo, and must not stay on the
// call site. The first line inside the body is the declaration line of Foo,
// captured above from its DebugFunction. If a compiler attributes the whole
// inlined body to the call site, stepping into Foo does not appear to enter it,
// and this assertion fails.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL1]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_LINE]] [[FOO_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[PARAM:%[a-zA-Z_0-9]+]] [[A]]
// CHECK: [[RESULT1:%[0-9]+]] = OpIMul %uint [[A]]

// After Foo returns from the first call, execution returns to the DebugScope
// of computeMain. The line table returns to the first call statement, and the
// computed result reaches result[0].
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
// a placeholder. The line table enters the lines of Foo a second time.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL2]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_LINE]] [[FOO_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[PARAM]] [[A_PLUS_1]]
// CHECK: [[RESULT2:%[0-9]+]] = OpIMul %uint [[A_PLUS_1]]

// After Foo returns from the second call, execution returns to the DebugScope
// of computeMain again. The line table returns to the second call statement,
// and the computed result reaches result[1].
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL2_LINE]] [[CALL2_LINE]]
// CHECK: OpStore {{%[0-9]+}} [[RESULT2]]

StructuredBuffer<uint> buffer0;
RWStructuredBuffer<uint> result;

uint Foo(uint x) {
    return x * 2;
}

[shader("compute")]
[numthreads(1,1,1)]
void computeMain(uint3 threadId : SV_DispatchThreadID)
{
    uint a = buffer0[0];
    result[0] = Foo(a);
    result[1] = Foo(a + 1);
}
