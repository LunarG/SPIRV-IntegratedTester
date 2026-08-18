// RUN: %slangc

// This test is the counterpart to inline_loop_call_site_unrolled.slang. That
// shader asks for the loop to be unrolled. This shader asks for the loop to be
// kept, with the HLSL [loop] attribute, which Slang accepts. A compiler must
// honor both requests, and the debug information must describe the shape that
// results.
//
// Note the difference from the unrolled test. Slang ignores the HLSL [unroll]
// attribute and needs its own [ForceUnroll] attribute. Slang does accept the
// HLSL [loop] attribute here.

// A DebugFunction must describe Foo, and a DebugInlinedAt must describe the
// call site.
//
// This test captures the declaration line of Foo, and the "inlined from" line
// of its call. Slang reports the declaration line of a callee on entry to its
// inlined body. These two captures are therefore edit-proof anchors for the
// line assertions below. This test needs no absolute line numbers.
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[FOO_LINE:%[a-zA-Z_0-9]+]] {{.*}}
// CHECK: [[CALL:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALL_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}}

// glslang with spirv-opt, and dxc, both move the loop counter to an OpPhi.
// Slang keeps `i` in real Function-storage memory instead.
//
// Slang still describes `i` with DebugValue, and not with DebugDeclare. The
// debug variable therefore tracks SSA values, while the real variable lives in
// memory. The debug information must describe the initial value, and the shader
// must store it.
// CHECK: %i = OpVariable {{.*}} Function
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %i_0 %uint_0
// CHECK: OpStore %i %uint_0

// The loop is still a loop, and the DontUnroll loop control bit carries the
// request to keep it. If a compiler drops that bit, the request of the shader
// author is lost before any consumer can act on it.
// CHECK: OpLoopMerge {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} DontUnroll

// The loop condition is a real run-time comparison against a real reload of the
// memory for `i`.
// CHECK: [[COND_I:%[0-9]+]] = OpLoad %uint %i
// CHECK: {{%[0-9]+}} = OpULessThan %bool [[COND_I]] %uint_2

// Inside the loop body, the shader reloads `i` one time. That single real value
// indexes both the destination and the source, so both sides of the assignment
// use the same iteration. Slang computes the destination pointer before it
// loads the source.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: [[IDX:%[0-9]+]] = OpLoad %uint %i
// CHECK: [[OUT:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 [[IDX]]
// CHECK: [[IN:%[0-9]+]] = OpAccessChain {{.*}} %buffer0 %int_0 [[IDX]]
// CHECK: [[VAL:%[0-9]+]] = OpLoad %uint [[IN]]

// Foo is still inlined, because inlining is independent of unrolling. The body
// of Foo therefore runs here, under a DebugScope that names Foo and the
// DebugInlinedAt of this call. It sits inside a loop that runs two times at run
// time. The real result of Foo reaches the destination above.
//
// The line table must enter the body of Foo and leave it again, even though the
// surrounding loop survives. It reports the declaration line of Foo inside the
// inlined body, then returns to the call statement before the store.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_LINE]] [[FOO_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %x [[VAL]]
// CHECK: [[RESULT:%[0-9]+]] = OpIMul %uint [[VAL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: OpStore [[OUT]] [[RESULT]]

// At the latch, the shader reloads `i`, increments it, and stores it back. The
// debug information describes each step. DebugValue must move to the updated
// value.
// CHECK: [[PREV:%[0-9]+]] = OpLoad %uint %i
// CHECK: %i_1 = OpIAdd %uint [[PREV]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %i_0 %i_1
// CHECK: OpStore %i %i_1

StructuredBuffer<uint> buffer0;
RWStructuredBuffer<uint> result;

uint Foo(uint x) {
    return x * 2;
}

[shader("compute")]
[numthreads(1,1,1)]
void computeMain(uint3 threadId : SV_DispatchThreadID)
{
    [loop]
    for (uint i = 0; i < 2; i++) {
        result[i] = Foo(buffer0[i]);
    }
}
