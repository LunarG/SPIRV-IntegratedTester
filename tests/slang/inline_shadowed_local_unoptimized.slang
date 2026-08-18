// RUN: %slangc -O0

// This shader is the same shadowing shader as inline_shadowed_local.slang,
// compiled at -O0.
//
// This test inlines nothing, so the two locals named `scale` live in two
// different functions. Each one has its own shadow variable and its own
// DebugDeclare, so a reader can tell them apart with ease.
//
// This behavior is the purpose of the variant. It fixes that both variables
// exist on their own before inlining. If this test passes and the optimized
// test fails, the fault is in the inliner, and not in the Slang front end.
//
// Note what -O0 turns off, and what it does not. Slang still folds both
// constants into the arithmetic. Foo multiplies by 5, and the caller adds 3.
// Neither value is ever reloaded from memory.
//
// The `_dbgvar_` stores exist for one purpose only: to give a debugger
// something to inspect. The real dataflow stays in SSA.
//
// Two instructions therefore describe each variable. A DebugDeclare points at
// its shadow memory, and a DebugValue carries its constant.

// Both variables share one name string, even in this test, where no reader can
// confuse them. Slang emits the names of the callee last.
// CHECK: [[MAIN_NAME:%[0-9]+]] = OpString "computeMain"
// CHECK: [[SCALE_NAME:%[0-9]+]] = OpString "scale"
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[X_NAME:%[0-9]+]] = OpString "x"

// The caller and its `scale` are both parented to computeMain.
// CHECK: [[MAIN:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[MAIN_NAME]]
// CHECK: %scale = OpExtInst {{.*}} DebugLocalVariable [[SCALE_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[MAIN]] {{.*}}

// The callee and its `scale` share the name string captured above. They are
// parented to Foo. At -O0, the debug variable for the parameter is named %x_0,
// because the OpFunctionParameter takes the name %x.
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]]
// CHECK: %x_0 = OpExtInst {{.*}} DebugLocalVariable [[X_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[FOO]] {{.*}}
// CHECK: %scale_0 = OpExtInst {{.*}} DebugLocalVariable [[SCALE_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[FOO]] {{.*}}

// The debug information does not describe the call as an inlined call.
//
// Keep this guard in place, between a declaration assertion and a body
// assertion. A CHECK-NOT directive searches only the span between the two
// matches around it. The compiler declares DebugInlinedAt in the module
// preamble. At the end of the file, this guard matches nothing and always
// passes.
// CHECK-NOT: {{DebugInlinedAt}}

// In computeMain, the `scale` of the caller has its own shadow variable. It
// also has its own DebugDeclare, bound to that variable, and its own DebugValue
// that carries 3.
// CHECK: %_dbgvar_scale = OpVariable {{.*}} Function
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare %scale %_dbgvar_scale {{%[a-zA-Z_0-9]+}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %scale %uint_3
// CHECK: OpStore %_dbgvar_scale %uint_3

// The shader makes a real call to Foo, by value. It then adds the constant of
// the caller to the result of that call.
// CHECK: [[OUT:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 %int_0
// CHECK: [[IN:%[0-9]+]] = OpAccessChain {{.*}} %buffer0 %int_0 %int_0
// CHECK: [[VAL:%[0-9]+]] = OpLoad %uint [[IN]]
// CHECK: [[CALL:%[0-9]+]] = OpFunctionCall %uint %Foo [[VAL]]
// CHECK: [[SUM:%[0-9]+]] = OpIAdd %uint [[CALL]] %uint_3
// CHECK: OpStore [[OUT]] [[SUM]]

// Inside Foo, the `scale` of the callee has a separate shadow variable, a
// separate DebugDeclare, and a DebugValue that carries 5.
//
// There are two variables, two allocations, and two DebugDeclare instructions.
// The two variables share the name string only.
// CHECK: %x = OpFunctionParameter %uint
// CHECK: %_dbgvar_scale_0 = OpVariable {{.*}} Function
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare %x_0 %_dbgvar_x {{%[a-zA-Z_0-9]+}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare %scale_0 %_dbgvar_scale_0 {{%[a-zA-Z_0-9]+}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %scale_0 %uint_5
// CHECK: OpStore %_dbgvar_scale_0 %uint_5

// The real computation of Foo reads its parameter directly.
// CHECK: [[PRODUCT:%[0-9]+]] = OpIMul %uint %x %uint_5
// CHECK: OpReturnValue [[PRODUCT]]

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
