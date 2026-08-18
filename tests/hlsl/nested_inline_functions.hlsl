// RUN: %dxc -T cs_6_0 -E computeMain

// This shader is the HLSL restatement of nested_inline_functions.slang.
// computeMain calls Bar, and Bar calls Foo. The dxc default inlines both
// calls. A DebugFunction must still describe Foo, and another must describe
// Bar. This test finds them by name.
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[BAR_NAME:%[0-9]+]] = OpString "Bar"
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]]
// CHECK: [[BAR:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[BAR_NAME]]

// dxc wraps the whole entry point in an internal DebugInlinedAt, which has no
// Inlined operand of its own. The assertion below steps past that wrapper.
//
// The call site of Bar (`Bar(a)`, inside computeMain) has its own
// DebugInlinedAt, tied back through that wrapper.
//
// The call site of Foo (`Foo(y)`, inside Bar) also has its own DebugInlinedAt.
// Its Inlined operand is the DebugInlinedAt of Bar, and not the one of the
// wrapper. This operand is what makes the chain describe a real two-level call
// stack, and not two independent, flat calls.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugInlinedAt {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}}
//
// This test captures the Line operand of each DebugInlinedAt. A debugger
// reports this line as the "inlined from" position for that frame of the call
// stack. The two lines must differ. Each line must also match the line that
// the line table reports for its own call statement, compared below.
// CHECK: [[CALL_BAR:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALL_BAR_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}}
// CHECK: [[CALL_FOO:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALL_FOO_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} [[CALL_BAR]]

// The shader loads `a` one time, with a real value.
// CHECK: [[A:%[0-9]+]] = OpLoad %uint

// The inlined body of Bar runs under a DebugScope. That scope names Bar and
// the DebugInlinedAt of Bar. The parameter of Bar must track the real value of
// `a`. On entry, the line table is on the call statement of computeMain, where
// the shader evaluates the argument.
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
// dxc reports the body statement of Foo, and not its declaration line. This
// test inlines Foo one time only, so no second copy exists to compare against.
// The requirement is therefore a CHECK-NOT guard over the region up to the
// multiply. If an inliner attributes the whole body of Foo to the call site,
// the call line stays in force here and the guard fails.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL_FOO]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_FOO_LINE]] [[CALL_FOO_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue {{%[a-zA-Z_0-9]+}} [[A]]
// CHECK-NOT: DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_FOO_LINE]] [[CALL_FOO_LINE]]
// CHECK: [[FOO_RESULT:%[0-9]+]] = OpIMul %uint [[A]]

// After Foo returns, execution leaves the DebugScope of Foo. The line table
// returns to the statement of Bar, which is the line that called Foo. The
// computed result of Foo then feeds the computation of Bar.
// CHECK-NOT: DebugScope [[FOO]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_FOO_LINE]] [[CALL_FOO_LINE]]
// CHECK: [[BAR_RESULT:%[0-9]+]] = OpIAdd %uint [[FOO_RESULT]]

// After Bar returns, execution leaves the DebugScope of Bar as well. The line
// table returns to the call statement of computeMain, and the computed result
// reaches result[0].
//
// With the assertions above, this is the full two-level walk:
// computeMain -> Bar -> Foo -> Bar -> computeMain.
// CHECK-NOT: DebugScope [[BAR]]
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

[numthreads(1,1,1)]
void computeMain(uint3 threadId : SV_DispatchThreadID)
{
    uint a = buffer0[0];
    result[0] = Bar(a);
}
