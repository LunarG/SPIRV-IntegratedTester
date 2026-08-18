// RUN: %slangc

// The [ForceUnroll] attribute forces the loop to unroll in full. The one call
// site of Foo in the source therefore becomes two separate call sites in the
// compiled code, one for each unrolled iteration. The Slang default still
// inlines both.
//
// A DebugFunction must still describe Foo. This test finds it by name.
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[FOO_LINE:%[a-zA-Z_0-9]+]] {{.*}}

// This test captures the "inlined from" line of the call, from a
// DebugInlinedAt. Both unrolled copies come from the same call site in the
// source, so both must report this same line. The assertions below cover each
// copy.
//
// This test does not pin how many DebugInlinedAt instructions Slang emits for
// that one call site. Slang emits one for each copy, and dxc reuses a single
// one. This test pins the line that they report only.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugInlinedAt [[CALL_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}}

// This is the first unrolled iteration. The loop counter must read 0 here. The
// load must come from buffer0[0]. The parameter of Foo must track that real
// value, and the real result must reach result[0].
//
// This test pins each access chain to its own base and constant index. A copy
// that reads or writes the wrong element therefore fails. Slang computes the
// destination pointer before it loads the source.
//
// The line table must enter the inlined copy of Foo. The line inside the copy
// is the declaration line of Foo, captured above from its DebugFunction. The
// line table must return to the call line before the store.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %i %uint_0
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: [[OUT0:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 %uint_0
// CHECK: [[IN0:%[0-9]+]] = OpAccessChain {{.*}} %buffer0 %int_0 %uint_0
// CHECK: [[BUF0:%[0-9]+]] = OpLoad %uint [[IN0]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] {{%[a-zA-Z_0-9]+}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_LINE]] [[FOO_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %x [[BUF0]]
// CHECK: [[RESULT0:%[0-9]+]] = OpIMul %uint [[BUF0]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: OpStore [[OUT0]] [[RESULT0]]

// This is the second unrolled iteration. The loop counter must read 1 here.
// This copy must read buffer0[1] and write result[1]. It must not use the
// element of the first iteration, and it must not use a placeholder.
//
// The line table must make the same excursion into Foo and back, and must
// report the same two lines. There is one call site, one callee, and two
// copies.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %i %uint_1
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: [[OUT1:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 %uint_1
// CHECK: [[IN1:%[0-9]+]] = OpAccessChain {{.*}} %buffer0 %int_0 %uint_1
// CHECK: [[BUF1:%[0-9]+]] = OpLoad %uint [[IN1]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] {{%[a-zA-Z_0-9]+}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_LINE]] [[FOO_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %x [[BUF1]]
// CHECK: [[RESULT1:%[0-9]+]] = OpIMul %uint [[BUF1]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: OpStore [[OUT1]] [[RESULT1]]

// After the last copy, the loop counter holds its exit value. This value, with
// the two copies above that carry constant indices, is what shows that the
// unroller unrolled the loop in full. A surviving loop cannot produce this
// shape.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %i %uint_2

StructuredBuffer<uint> buffer0;
RWStructuredBuffer<uint> result;

uint Foo(uint x) {
    return x * 2;
}

[shader("compute")]
[numthreads(1,1,1)]
void computeMain(uint3 threadId : SV_DispatchThreadID)
{
    [ForceUnroll]
    for (uint i = 0; i < 2; i++) {
        result[i] = Foo(buffer0[i]);
    }
}
