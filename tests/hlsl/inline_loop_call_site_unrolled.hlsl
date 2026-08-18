// RUN: %dxc -T cs_6_0 -E computeMain

// This shader is the HLSL restatement of
// inline_loop_call_site_unrolled.slang. The [unroll] attribute forces the loop
// to unroll in full. The one call site of Foo in the source therefore becomes
// two separate call sites in the compiled code, one for each unrolled
// iteration. The dxc default still inlines both.
//
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
// one for the call site of Foo. It then captures the Line operand, which a
// debugger reports as the "inlined from" position.
//
// Both unrolled copies come from the same call site in the source, so both must
// report this same line. The assertions below cover each copy.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugInlinedAt {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugInlinedAt [[CALL_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}}

// This is the first unrolled iteration. The loop counter must read 0 here. The
// load must come from buffer0[0]. The parameter of Foo must track that real
// value, and the real result must reach result[0].
//
// This test pins each access chain to its own base and constant index. A copy
// that reads or writes the wrong element therefore fails. dxc loads the source
// before it computes the destination pointer.
//
// At the arithmetic of Foo, the line table must have left the call line and
// moved to a line of Foo. This move is what makes stepping into Foo appear to
// enter it.
//
// dxc reports the body statement of Foo, and not its declaration line. Both
// unrolled copies share the same call line, so neither the DebugFunction of Foo
// nor the other copy can serve as a positive anchor. The requirement is
// therefore a CHECK-NOT guard over the region up to the multiply.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[I]] %uint_0
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: [[IN0:%[0-9]+]] = OpAccessChain {{.*}} %buffer0 %int_0 %uint_0
// CHECK: [[BUF0:%[0-9]+]] = OpLoad %uint [[IN0]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] {{%[a-zA-Z_0-9]+}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[X]] [[BUF0]]
// CHECK-NOT: DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: [[RESULT0:%[0-9]+]] = OpIMul %uint [[BUF0]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: [[OUT0:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 %uint_0
// CHECK: OpStore [[OUT0]] [[RESULT0]]

// This is the second unrolled iteration. The loop counter must read 1 here.
// This copy must read buffer0[1] and write result[1]. It must not use the
// element of the first iteration, and it must not use a placeholder.
//
// dxc reuses one DebugInlinedAt across both unrolled copies. Slang emits a new
// one for each copy. This test pins neither choice. It pins the identity of Foo
// only. The line table must make the same excursion into Foo and back.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[I]] %uint_1
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: [[IN1:%[0-9]+]] = OpAccessChain {{.*}} %buffer0 %int_0 %uint_1
// CHECK: [[BUF1:%[0-9]+]] = OpLoad %uint [[IN1]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] {{%[a-zA-Z_0-9]+}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[X]] [[BUF1]]
// CHECK-NOT: DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: [[RESULT1:%[0-9]+]] = OpIMul %uint [[BUF1]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALL_LINE]] [[CALL_LINE]]
// CHECK: [[OUT1:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 %uint_1
// CHECK: OpStore [[OUT1]] [[RESULT1]]

// After the last copy, the loop counter holds its exit value. This value, with
// the two copies above that carry constant indices, is what shows that the
// unroller unrolled the loop in full. A surviving loop cannot produce this
// shape.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue [[I]] %uint_2

StructuredBuffer<uint> buffer0;
RWStructuredBuffer<uint> result;

uint Foo(uint x) {
    return x * 2;
}

[numthreads(1,1,1)]
void computeMain(uint3 threadId : SV_DispatchThreadID)
{
    [unroll]
    for (uint i = 0; i < 2; i++) {
        result[i] = Foo(buffer0[i]);
    }
}
