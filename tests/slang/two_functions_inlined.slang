// RUN: %slangc

// This test uses a different inlining shape from inline_functions.slang.
// computeMain calls two different functions, Foo and Bar, one time each. The
// Slang default inlines both calls.
//
// A DebugFunction must still describe each of computeMain, Foo, and Bar. This
// test finds them by name.
// CHECK: [[MAIN_NAME:%[0-9]+]] = OpString "computeMain"
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[BAR_NAME:%[0-9]+]] = OpString "Bar"
//
// This test captures the declaration line of Foo and of Bar from their own
// DebugFunction. Slang reports the declaration line of a callee on entry to
// its inlined body. These two captures are therefore edit-proof anchors for
// the line assertions below. This test needs no absolute line numbers.
// CHECK: [[MAIN:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[MAIN_NAME]]
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[FOO_LINE:%[a-zA-Z_0-9]+]] {{.*}}
// CHECK: [[BAR:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[BAR_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[BAR_LINE:%[a-zA-Z_0-9]+]] {{.*}}

// Each call site has its own DebugInlinedAt, and both tie back to computeMain.
//
// This test captures both Line operands. A debugger reports this line as the
// "inlined from" position in a call stack. The two lines must differ, because
// the two calls are on different lines.
// CHECK: [[CALL_FOO:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALL_FOO_LINE:%[a-zA-Z_0-9]+]] [[MAIN]]
// CHECK: [[CALL_BAR:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALL_BAR_LINE:%[a-zA-Z_0-9]+]] [[MAIN]]

// The shader loads `a` one time, with a real value. The line table then moves
// to the first call statement.
// CHECK: [[A:%[0-9]+]] = OpLoad %uint
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_FOO_LINE]] [[CALL_FOO_LINE]]

// The call `Foo(a)` runs under a DebugScope. That scope names Foo and the
// DebugInlinedAt of Foo. The parameter of Foo must track the real value of `a`.
// The computation that runs here must be the one of Foo, which multiplies by
// two, and not the one of Bar.
//
// The line table must enter the body of Foo. The line here is the declaration
// line of Foo, and not the call site.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL_FOO]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_LINE]] [[FOO_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue {{%[a-zA-Z_0-9]+}} [[A]]
// CHECK: [[FOO_RESULT:%[0-9]+]] = OpIMul %uint [[A]]

// After Foo returns, execution returns to the DebugScope of computeMain. The
// line table returns to the first call statement, and the real result of Foo
// reaches result[0].
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_FOO_LINE]] [[CALL_FOO_LINE]]
// CHECK: OpStore {{%[0-9]+}} [[FOO_RESULT]]

// The line table advances to the second call statement. The call `Bar(a)` then
// runs under a DebugScope that names Bar and the DebugInlinedAt of Bar. Both
// differ from the DebugFunction and the DebugInlinedAt of the call to Foo.
//
// The parameter of Bar must also track the real value of `a`. The computation
// that runs here must be the one of Bar, which adds 100, and not the one of
// Foo. The line inside the body is the declaration line of Bar, which differs
// from the one of Foo.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_BAR_LINE]] [[CALL_BAR_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[BAR]] [[CALL_BAR]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[BAR_LINE]] [[BAR_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue {{%[a-zA-Z_0-9]+}} [[A]]
// CHECK: [[BAR_RESULT:%[0-9]+]] = OpIAdd %uint [[A]]

// After Bar returns, execution returns to the DebugScope of computeMain again.
// The line table returns to the second call statement, and the real result of
// Bar reaches result[1].
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_BAR_LINE]] [[CALL_BAR_LINE]]
// CHECK: OpStore {{%[0-9]+}} [[BAR_RESULT]]

StructuredBuffer<uint> buffer0;
RWStructuredBuffer<uint> result;

uint Foo(uint x) {
    return x * 2;
}

uint Bar(uint y) {
    return y + 100;
}

[shader("compute")]
[numthreads(1,1,1)]
void computeMain(uint3 threadId : SV_DispatchThreadID)
{
    uint a = buffer0[0];
    result[0] = Foo(a);
    result[1] = Bar(a);
}
