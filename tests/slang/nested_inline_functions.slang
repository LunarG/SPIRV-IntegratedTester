// RUN: %slangc

// This shader extends the "Inline Functions" checklist item of issue #9 with a
// second level. computeMain calls Bar, and Bar calls Foo. The Slang default
// inlines both calls. A DebugFunction must still describe each of the three
// functions. This test finds them by name.
// CHECK: [[MAIN_NAME:%[0-9]+]] = OpString "computeMain"
// CHECK: [[BAR_NAME:%[0-9]+]] = OpString "Bar"
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
//
// This test captures the declaration line of Bar and of Foo from their own
// DebugFunction. Slang reports the declaration line of a callee on entry to
// its inlined body. These two captures are therefore edit-proof anchors for
// the line assertions below. This test needs no absolute line numbers.
// CHECK: [[MAIN:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[MAIN_NAME]]
// CHECK: [[BAR:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[BAR_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[BAR_LINE:%[a-zA-Z_0-9]+]] {{.*}}
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[FOO_LINE:%[a-zA-Z_0-9]+]] {{.*}}

// The call site of Bar (`Bar(a)`, inside computeMain) has its own
// DebugInlinedAt, tied back to computeMain.
//
// The call site of Foo (`Foo(y)`, inside Bar) has its own DebugInlinedAt, tied
// to Bar. Its Inlined operand is the DebugInlinedAt of Bar, and not the one of
// computeMain. This operand is what makes the chain describe a real two-level
// call stack, and not two independent, flat calls.
//
// This test captures the Line operand of each DebugInlinedAt. A debugger
// reports this line as the "inlined from" position for that frame of the call
// stack. The two lines must differ. Each line must also match the line that
// the line table reports for its own call statement, compared below.
// CHECK: [[CALL_BAR:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALL_BAR_LINE:%[a-zA-Z_0-9]+]] [[MAIN]]
// CHECK: [[CALL_FOO:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALL_FOO_LINE:%[a-zA-Z_0-9]+]] [[BAR]] [[CALL_BAR]]

// The shader loads `a` one time, with a real value. The line table then moves
// to the call statement of computeMain.
// CHECK: [[A:%[0-9]+]] = OpLoad %uint
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_BAR_LINE]] [[CALL_BAR_LINE]]

// The inlined body of Bar runs under a DebugScope. That scope names Bar and
// the DebugInlinedAt of Bar. The parameter of Bar must track the real value of
// `a`.
//
// The line table must enter the body of Bar. The line here is the declaration
// line of Bar, captured above from its DebugFunction. It is not the call site
// that Bar was inlined at.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[BAR]] [[CALL_BAR]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[BAR_LINE]] [[BAR_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue {{%[a-zA-Z_0-9]+}} [[A]]

// The inlined body of Foo sits inside the body of Bar. It runs under a
// DebugScope that names Foo and the DebugInlinedAt of Foo, and not the one of
// Bar. The parameter of Foo must also track the real value of `a`, carried
// through Bar. The line table moves down a second level, to the declaration
// line of Foo.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL_FOO]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_LINE]] [[FOO_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue {{%[a-zA-Z_0-9]+}} [[A]]
// CHECK: [[FOO_RESULT:%[0-9]+]] = OpIMul %uint [[A]]

// After Foo returns, execution returns to the DebugScope of Bar. The line
// table returns to the statement of Bar, which is the line that called Foo.
// The computed result of Foo then feeds the computation of Bar.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[BAR]] [[CALL_BAR]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_FOO_LINE]] [[CALL_FOO_LINE]]
// CHECK: [[BAR_RESULT:%[0-9]+]] = OpIAdd %uint [[FOO_RESULT]]

// After Bar returns, execution returns to the DebugScope of computeMain. The
// line table returns to the call statement of computeMain, and the computed
// result reaches result[0].
//
// With the assertions above, this is the full two-level walk, in four distinct
// line values: computeMain -> Bar -> Foo -> Bar -> computeMain.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_BAR_LINE]] [[CALL_BAR_LINE]]
// CHECK: OpStore {{%[0-9]+}} [[BAR_RESULT]]

StructuredBuffer<uint> buffer0;
RWStructuredBuffer<uint> result;

uint Foo(uint x) {
    return x * 2;
}

uint Bar(uint y) {
    return Foo(y) + 1;
}

[shader("compute")]
[numthreads(1,1,1)]
void computeMain(uint3 threadId : SV_DispatchThreadID)
{
    uint a = buffer0[0];
    result[0] = Bar(a);
}
