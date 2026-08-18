// RUN: %slangc

// Foo declares a local named `scale`, and computeMain declares one too. Slang
// inlines Foo, so both locals sit in the same function body at the same time.
// The debug information is then the only thing that can tell them apart.
//
// The name cannot tell them apart. The module holds one OpString "scale" only,
// and both variables share it. The identity of each variable lives in the
// Parent operand of its DebugLocalVariable.
//
// Slang parents locals directly to the DebugFunction, as glslang does. dxc
// inserts a DebugLexicalBlock instead. Slang also declares the variable of the
// caller before the one of the callee. The other two compilers use the opposite
// order.

// Both variables share one name string. Slang emits the names of the callee
// last, so "Foo" and "x" appear after "scale".
// CHECK: [[MAIN_NAME:%[0-9]+]] = OpString "computeMain"
// CHECK: [[SCALE_NAME:%[0-9]+]] = OpString "scale"
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[X_NAME:%[0-9]+]] = OpString "x"

// The caller and its `scale` are both parented to computeMain.
// CHECK: [[MAIN:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[MAIN_NAME]]
// CHECK: %scale = OpExtInst {{.*}} DebugLocalVariable [[SCALE_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[MAIN]] {{.*}}

// The callee and its `scale` share the name string captured above. They are
// parented to Foo. This difference is the whole contract that this test exists
// for.
//
// Slang names the two debug variables %scale and %scale_0, so this test names
// them directly. This test captures the declaration line of the callee here,
// and compares it against the line table below. This test needs no absolute
// line numbers.
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]]
// CHECK: %x = OpExtInst {{.*}} DebugLocalVariable [[X_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[FOO]] {{.*}}
// CHECK: %scale_0 = OpExtInst {{.*}} DebugLocalVariable [[SCALE_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[CALLEE_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} [[FOO]] {{.*}}
// CHECK: [[CALL:%[0-9]+]] = OpExtInst {{.*}} DebugInlinedAt [[CALLER_LINE:%[a-zA-Z_0-9]+]] [[MAIN]]

// In the scope of the caller, the `scale` of the caller holds 3. The DebugValue
// binds to %scale. This binding is the proof that the value reached the
// variable of the caller, and not the one of the callee.
//
// Slang emits each DebugValue two times. This test asserts the first one
// only.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %scale %uint_3

// The line table must be on the call site here. This test captured
// [[CALLER_LINE]] above, from DebugInlinedAt. This assertion therefore also
// compares the "inlined from" line against the line that the line table
// reports for the call statement. Slang computes the destination pointer before loading
// the source.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALLER_LINE]] [[CALLER_LINE]]
// CHECK: [[OUT:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 %int_0
// CHECK: [[IN:%[0-9]+]] = OpAccessChain {{.*}} %buffer0 %int_0 %int_0
// CHECK: [[VAL:%[0-9]+]] = OpLoad %uint [[IN]]

// Execution enters the inlined body of Foo. The line table must enter the body
// of the callee, and must not stay on the call site. The line here is the line
// that declares the `scale` of the callee.
//
// If the inliner attributes the whole inlined body to the call site, stepping
// into Foo does not appear to enter it, and this assertion fails.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]] [[CALL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %x [[VAL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALLEE_LINE]] [[CALLEE_LINE]]

// The `scale` of the callee holds 5, and its real multiply uses that
// value.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %scale_0 %uint_5
// CHECK: [[PRODUCT:%[0-9]+]] = OpIMul %uint [[VAL]] %uint_5

// Execution leaves the inlined body. The scope returns to the caller, and the
// line table returns to the statement line of the caller.
//
// The arithmetic after this point uses the 3 of the caller, and not the 5 of
// the callee. The two variables therefore stayed distinct across the whole
// inlined region.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[CALLER_LINE]] [[CALLER_LINE]]
// CHECK: [[SUM:%[0-9]+]] = OpIAdd %uint [[PRODUCT]] %uint_3
// CHECK: OpStore [[OUT]] [[SUM]]

StructuredBuffer<uint> buffer0;
RWStructuredBuffer<uint> result;

uint Foo(uint x) {
    uint scale = 5;
    return x * scale;
}

[shader("compute")]
[numthreads(1,1,1)]
void computeMain(uint3 threadId : SV_DispatchThreadID)
{
    uint scale = 3;
    result[0] = Foo(buffer0[0]) + scale;
}
