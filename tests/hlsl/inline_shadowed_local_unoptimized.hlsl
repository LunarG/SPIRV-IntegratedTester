// RUN: %dxc -T cs_6_0 -E computeMain -Od

// This shader is the same shadowing shader as inline_shadowed_local.hlsl. This
// test turns off the dxc optimizations.
//
// This test inlines nothing, so the two locals named `scale` live in two
// different functions. Each one is its own Function-storage variable, with its
// own DebugDeclare, so a reader can tell them apart with ease.
//
// This behavior is the purpose of the variant. It fixes that both variables
// exist on their own before inlining. If this test passes and the optimized
// test fails, the fault is in the inliner, and not in the dxc front end.

// Both variables share one name string, even in this test, where no reader can
// confuse them.
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[SCALE_NAME:%[0-9]+]] = OpString "scale"
// CHECK: [[X_NAME:%[0-9]+]] = OpString "x"
// CHECK: [[MAIN_NAME:%[0-9]+]] = OpString "computeMain"

// These three assertions cover Foo, the lexical block of Foo, and the `scale`
// of the callee, which is parented to that block. dxc parents locals to a
// DebugLexicalBlock, and not directly to the DebugFunction, so this test
// asserts both links of the chain.
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]]
// CHECK: [[FOO_BLOCK:%[0-9]+]] = OpExtInst {{.*}} DebugLexicalBlock {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[FOO]]
// CHECK: [[SCALE_CALLEE:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[SCALE_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[FOO_BLOCK]] {{.*}}
// CHECK: [[X:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[X_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[FOO]] {{.*}}

// These assertions cover the same three levels for the caller. The `scale` of
// the caller shares the name string captured above. It is parented to the block
// of computeMain, and not to the block of Foo.
// CHECK: [[MAIN:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[MAIN_NAME]]
// CHECK: [[MAIN_BLOCK:%[0-9]+]] = OpExtInst {{.*}} DebugLexicalBlock {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[MAIN]]
// CHECK: [[SCALE_CALLER:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[SCALE_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[MAIN_BLOCK]] {{.*}}

// The debug information does not describe the call as an inlined call.
//
// Keep this guard in place, between a declaration assertion and a body
// assertion. A CHECK-NOT directive searches only the span between the two
// matches around it. The compiler declares DebugInlinedAt in the module
// preamble. At the end of the file, this guard matches nothing and always
// passes.
// CHECK-NOT: {{DebugInlinedAt}}

// In src_computeMain, the `scale` of the caller is real Function-storage memory
// that holds 3. A DebugDeclare describes it and binds to that memory.
//
// dxc emits the store before the DebugDeclare. glslang uses the opposite order.
// The disassembler names this one %scale, and the one in Foo %scale_0, because
// src_computeMain comes first in the module.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN_BLOCK]]
// CHECK: OpStore %scale %uint_3
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[SCALE_CALLER]] %scale {{%[a-zA-Z_0-9]+}}

// The shader makes a real call to Foo. It also reloads the `scale` of the
// caller from its own memory, and adds that value to the result.
// CHECK: [[IN:%[0-9]+]] = OpAccessChain {{.*}} %buffer0 %int_0 %uint_0
// CHECK: [[VAL:%[0-9]+]] = OpLoad %uint [[IN]]
// CHECK: OpStore %param_var_x [[VAL]]
// CHECK: [[CALL:%[0-9]+]] = OpFunctionCall %uint %Foo %param_var_x
// CHECK: [[CALLER_SCALE:%[0-9]+]] = OpLoad %uint %scale
// CHECK: [[SUM:%[0-9]+]] = OpIAdd %uint [[CALL]] [[CALLER_SCALE]]
// CHECK: [[OUT:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 %uint_0
// CHECK: OpStore [[OUT]] [[SUM]]

// Inside Foo, the `scale` of the callee is a separate Function-storage variable
// that holds 5. Its own DebugDeclare binds to its own memory.
//
// There are two variables, two allocations, and two DebugDeclare instructions.
// The two variables share the name string only. Each sits under its own scope: Foo's function scope for the
// parameter, Foo's lexical block for the body.
// CHECK: %x = OpFunctionParameter {{.*}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[X]] %x {{%[a-zA-Z_0-9]+}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO_BLOCK]]
// CHECK: OpStore %scale_0 %uint_5
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[SCALE_CALLEE]] %scale_0 {{%[a-zA-Z_0-9]+}}

// The real computation of Foo reads both its parameter and its own
// `scale`.
// CHECK: [[FOO_X:%[0-9]+]] = OpLoad %uint %x
// CHECK: [[FOO_SCALE:%[0-9]+]] = OpLoad %uint %scale_0
// CHECK: [[PRODUCT:%[0-9]+]] = OpIMul %uint [[FOO_X]] [[FOO_SCALE]]
// CHECK: OpReturnValue [[PRODUCT]]

StructuredBuffer<uint> buffer0;
RWStructuredBuffer<uint> result;

uint Foo(uint x) {
    uint scale = 5;
    return x * scale;
}

[numthreads(1,1,1)]
void computeMain(uint3 threadId : SV_DispatchThreadID)
{
    uint scale = 3;
    result[0] = Foo(buffer0[0]) + scale;
}
