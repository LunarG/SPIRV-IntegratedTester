// RUN: %dxc -T cs_6_0 -E computeMain -Od

// This shader is the same [unroll] shader as
// inline_loop_call_site_unrolled.hlsl. This test turns off the dxc
// optimizations.
//
// dxc does not act on the attribute here. It records the request as the Unroll
// loop control bit on OpLoopMerge, and leaves the loop standing for a
// downstream consumer to unroll. Slang at -O0 behaves differently. dxc does not
// inline Foo either.

// Three items must each have their own debug instruction: Foo, the parameter
// `x` of Foo, and the loop counter `i`. This test finds them by name.
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[X_NAME:%[0-9]+]] = OpString "x"
// CHECK: [[I_NAME:%[0-9]+]] = OpString "i"
// CHECK: [[X:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[X_NAME]]
// CHECK: [[I:%[0-9]+]] = OpExtInst {{.*}} DebugLocalVariable [[I_NAME]]

// The debug information does not describe the call as an inlined call.
//
// Keep this guard in place, between a declaration assertion and a body
// assertion. A CHECK-NOT directive searches only the span between the two
// matches around it. The compiler declares DebugInlinedAt in the module
// preamble. At the end of the file, this guard matches nothing and always
// passes.
// CHECK-NOT: {{DebugInlinedAt}}

// `i` is real Function-storage memory, and it starts at 0. A DebugDeclare
// describes it and binds to that memory. This test has no DebugValue
// instruction for each copy, because it has no copies. `i` is a real run-time
// variable.
// CHECK: OpStore %i %uint_0
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[I]] %i {{%[a-zA-Z_0-9]+}}

// The loop survives, and the Unroll loop control bit carries the unroll request
// with it. If a compiler drops that bit, the request of the shader author is
// lost before any consumer can act on it.
// CHECK: OpLoopMerge {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} Unroll

// The shader has one loop body. Inside it, real loads of `i` index both the
// source and the destination. Neither index is a constant. dxc passes the
// argument by pointer to real Function-storage memory.
// CHECK: [[IDX_IN:%[0-9]+]] = OpLoad %uint %i
// CHECK: [[IN:%[0-9]+]] = OpAccessChain {{.*}} %buffer0 %int_0 [[IDX_IN]]
// CHECK: [[VAL:%[0-9]+]] = OpLoad %uint [[IN]]
// CHECK: OpStore %param_var_x [[VAL]]
// CHECK: [[CALL:%[0-9]+]] = OpFunctionCall %uint %Foo %param_var_x
// CHECK: [[IDX_OUT:%[0-9]+]] = OpLoad %uint %i
// CHECK: [[OUT:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 [[IDX_OUT]]
// CHECK: OpStore [[OUT]] [[CALL]]

// The shader increments the loop counter at run time.
// CHECK: [[PREV:%[0-9]+]] = OpLoad %uint %i
// CHECK: [[NEXT:%[0-9]+]] = OpIAdd %uint [[PREV]] %uint_1
// CHECK: OpStore %i [[NEXT]]

// The parameter of Foo is real Function-storage memory, and its own
// DebugDeclare describes it. The real computation of Foo runs inside Foo.
// CHECK: %x = OpFunctionParameter {{.*}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[X]] %x {{%[a-zA-Z_0-9]+}}
// CHECK: [[FOO_X:%[0-9]+]] = OpLoad %uint %x
// CHECK: [[FOO_RESULT:%[0-9]+]] = OpIMul %uint [[FOO_X]]
// CHECK: OpReturnValue [[FOO_RESULT]]

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
