// RUN: %dxc -T cs_6_0 -E computeMain

// This shader is the HLSL restatement of two_functions_inlined.slang.
// computeMain calls two different functions, Foo and Bar, one time each. The
// dxc default inlines both calls.
//
// A DebugFunction must still describe Foo, and another must describe Bar. This
// test finds them by name. dxc emits them in a different order from the source
// declarations, and the name string of Bar comes first. This order is internal
// to dxc, and the contract does not fix it.
// CHECK: [[BAR_NAME:%[0-9]+]] = OpString "Bar"
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[BAR:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[BAR_NAME]]
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]]

// dxc emits an internal top-level wrapper DebugInlinedAt, which has no Inlined
// operand of its own. The assertion below steps past that wrapper. The call
// site of Foo and the call site of Bar each have their own DebugInlinedAt, tied
// back through that wrapper.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugInlinedAt {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}}

// This test captures both Line operands. A debugger reports this line as the
// "inlined from" position in a call stack. The two lines must differ, because
// the two calls are on different lines.
// CHECK: [[CALL_FOO:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALL_FOO_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}}
// CHECK: [[CALL_BAR:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALL_BAR_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}}

// The shader loads `a` one time, with a real value.
// CHECK: [[A:%[0-9]+]] = OpLoad %uint

// The call `Foo(a)` runs under a DebugScope. That scope names Foo and the
// DebugInlinedAt of Foo. The parameter of Foo must track the real value of `a`.
// The computation that runs here must be the one of Foo, which multiplies by
// two, and not the one of Bar. On entry, the line table is on the call
// statement, where the shader evaluates the argument.
//
// At the arithmetic of Foo, the line table must have left that call line and
// moved to a line of Foo. This move is what makes stepping into Foo appear to
// enter it.
//
// dxc reports the body statement of Foo, and not its declaration line. This
// test inlines Foo one time only, so no second copy exists to compare against.
// The requirement is therefore a CHECK-NOT guard over the region up to the
// multiply.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL_FOO]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_FOO_LINE]] [[CALL_FOO_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue {{%[a-zA-Z_0-9]+}} [[A]]
// CHECK-NOT: DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_FOO_LINE]] [[CALL_FOO_LINE]]
// CHECK: [[FOO_RESULT:%[0-9]+]] = OpIMul %uint [[A]]

// After Foo returns, execution leaves the DebugScope of Foo. The line table
// returns to the first call statement, and the real result of Foo reaches
// result[0].
// CHECK-NOT: DebugScope [[FOO]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_FOO_LINE]] [[CALL_FOO_LINE]]
// CHECK: OpStore {{%[0-9]+}} [[FOO_RESULT]]

// The call `Bar(a)` runs under a DebugScope. That scope names Bar and the
// DebugInlinedAt of Bar. Both differ from the DebugFunction and the
// DebugInlinedAt of the call to Foo.
//
// The parameter of Bar must also track the real value of `a`. The computation
// that runs here must be the one of Bar, which adds 100, and not the one of
// Foo. The same line requirement applies, against the call line of Bar.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[BAR]] [[CALL_BAR]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_BAR_LINE]] [[CALL_BAR_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue {{%[a-zA-Z_0-9]+}} [[A]]
// CHECK-NOT: DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_BAR_LINE]] [[CALL_BAR_LINE]]
// CHECK: [[BAR_RESULT:%[0-9]+]] = OpIAdd %uint [[A]]

// After Bar returns, execution leaves the DebugScope of Bar. The line table
// returns to the second call statement, and the real result of Bar reaches
// result[1].
// CHECK-NOT: DebugScope [[BAR]]
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

[numthreads(1,1,1)]
void computeMain(uint3 threadId : SV_DispatchThreadID)
{
    uint a = buffer0[0];
    result[0] = Foo(a);
    result[1] = Bar(a);
}
