// RUN: %dxc -T cs_6_0 -E computeMain

// This test is the counterpart to inline_loop_call_site_unrolled.hlsl. That
// shader asks for the loop to be unrolled. This shader asks for the loop to be
// kept, with the HLSL [loop] attribute. A compiler must honor both requests,
// and the debug information must describe the shape that results.

// Three items must each have their own debug instruction: Foo, the parameter
// `x` of Foo, and the loop counter `i`. This test finds them by name.
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[X_NAME:%[0-9]+]] = OpString "x"
// CHECK: [[I_NAME:%[0-9]+]] = OpString "i"
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]]
// CHECK: [[X:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[X_NAME]]
// CHECK: [[I:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[I_NAME]]

// dxc emits an internal top-level wrapper DebugInlinedAt, which has no Inlined
// operand of its own. The assertion below steps past that wrapper, to reach the
// one for the call site of Foo.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugInlinedAt {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}}
// CHECK: [[CALL:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALL_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}}

// Before execution enters the loop, `i` holds its initial value.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[I]] %uint_0

// `i` is never real memory in this test. dxc keeps it in SSA form, as a
// loop-carried OpPhi. The incoming value of that phi from outside the loop is
// the same initial constant.
//
// The Value operand of DebugValue for `i` must be the phi itself. A debugger
// then reads the value of the current iteration, and not a stale value or a
// placeholder. The loop condition tests that same phi.
// CHECK: [[PHI:%[0-9]+]] = OpPhi %uint %uint_0 {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[I]] [[PHI]]
// CHECK: {{%[0-9]+}} = OpULessThan %bool [[PHI]] %uint_2

// The loop is still a loop, and the DontUnroll loop control bit carries the
// request to keep it. If a compiler drops that bit, the request of the shader
// author is lost before any consumer can act on it.
// CHECK: OpLoopMerge {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} DontUnroll

// Inside the loop body, the phi indexes the source element. Foo is still
// inlined, because inlining is independent of unrolling. The body of Foo
// therefore runs here, under a DebugScope that names Foo and the DebugInlinedAt
// of this call. It sits inside a loop that runs two times at run time. On
// entry, the line table is on the call statement.
//
// At the arithmetic of Foo, the line table must have left that call line and
// moved to a line of Foo. This move is what makes stepping into Foo appear to
// enter it, even though the surrounding loop survives.
//
// dxc reports the body statement of Foo, and not its declaration line. This
// test inlines Foo one time only, so no second copy exists to compare against.
// The requirement is therefore a CHECK-NOT guard over the region up to the
// multiply.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: [[IN:%[0-9]+]] = OpAccessChain {{.*}} %buffer0 %int_0 [[PHI]]
// CHECK: [[VAL:%[0-9]+]] = OpLoad %uint [[IN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[X]] [[VAL]]
// CHECK-NOT: DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: [[RESULT:%[0-9]+]] = OpIMul %uint [[VAL]]

// The line table returns to the call statement. That same phi indexes the
// destination element, so both sides of the assignment use the same
// iteration.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: [[OUT:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 [[PHI]]
// CHECK: OpStore [[OUT]] [[RESULT]]

// At the end of the body, the shader increments `i`. DebugValue must move to
// the updated value.
// CHECK: [[NEXT:%[0-9]+]] = OpIAdd %uint [[PHI]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[I]] [[NEXT]]

StructuredBuffer<uint> buffer0;
RWStructuredBuffer<uint> result;

uint Foo(uint x) {
    return x * 2;
}

[numthreads(1,1,1)]
void computeMain(uint3 threadId : SV_DispatchThreadID)
{
    [loop]
    for (uint i = 0; i < 2; i++) {
        result[i] = Foo(buffer0[i]);
    }
}
