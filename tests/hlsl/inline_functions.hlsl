// RUN: %dxc -T cs_6_0 -E computeMain

// This shader is the "Inline Functions" checklist item of issue #9:
// https://godbolt.org/z/hbzq4zz71
//
// dxc inlines Foo into computeMain by default. A DebugFunction must still
// describe Foo. This test finds it by name, and not by position. The contract
// does not fix which one dxc emits first.
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]]

// The call `Foo(a)` and the call `Foo(a + 1)` are two separate call sites. A
// DebugInlinedAt instruction must describe each call site, and the compiler
// must never merge the two calls into one.
//
// dxc emits an internal top-level wrapper DebugInlinedAt, which has no Inlined
// operand of its own. The first assertion below steps past that wrapper to
// reach the two instructions for Foo.
//
// This test captures each Line operand. A debugger reports this line as the
// "inlined from" position in a call stack, so the two lines must differ. Each
// line must also match the line that the line table reports for its own call
// statement. The assertions below compare both.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugInlinedAt {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}}
// CHECK: [[CALL1:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALL1_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}}
// CHECK: [[CALL2:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALL2_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}}

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
// dxc reports the body statement, and not the declaration line of Foo. This
// test therefore cannot compare the captured line against the DebugFunction of
// Foo. Instead, the second inlined copy below reuses this line, where the
// surrounding call line differs.
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
// Foo. The line table returns to the first call statement, and the computed
// result reaches result[0].
// CHECK-NOT: DebugScope [[FOO]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL1_LINE]] [[CALL1_LINE]]
// CHECK: OpStore {{%[0-9]+}} [[RESULT1]]

// The line table advances to the second call statement, which is a different
// line from the first. The shader then computes `a + 1` one time, with a real
// value.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL2_LINE]] [[CALL2_LINE]]
// CHECK: [[A_PLUS_1:%[0-9]+]] = OpIAdd %uint [[A]]

// The inlined body of Foo for the second call, `Foo(a + 1)`, runs under a
// DebugScope. That scope names Foo and the DebugInlinedAt of the second call,
// which is a different instruction from the first. The parameter of Foo must
// track the real value of `a + 1`. It must not track the value of the first
// call, and it must not be a placeholder. The body line must be the same line
// that Foo reported in the first copy.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL2]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[PARAM]] [[A_PLUS_1]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_BODY_LINE]] [[FOO_BODY_LINE]]
// CHECK: [[RESULT2:%[0-9]+]] = OpIMul %uint [[A_PLUS_1]]

// After Foo returns from the second call, execution leaves the DebugScope of
// Foo again. The line table returns to the second call statement, and the
// computed result reaches result[1].
// CHECK-NOT: DebugScope [[FOO]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL2_LINE]] [[CALL2_LINE]]
// CHECK: OpStore {{%[0-9]+}} [[RESULT2]]

StructuredBuffer<uint> buffer0;
RWStructuredBuffer<uint> result;

uint Foo(uint x) {
    return x * 2;
}

[numthreads(1,1,1)]
void computeMain(uint3 threadId : SV_DispatchThreadID)
{
    uint a = buffer0[0];
    result[0] = Foo(a);
    result[1] = Foo(a + 1);
}
