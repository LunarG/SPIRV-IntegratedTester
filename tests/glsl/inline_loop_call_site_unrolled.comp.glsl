// RUN: %glslang

// This shader is the same [[unroll]] shader as
// inline_loop_call_site_unrolled_optimized.comp.glsl, without the %spirv_opt
// step.
//
// This test shows how the two tools divide the work. glslang records the
// request as the Unroll loop control bit on OpLoopMerge, and leaves the loop
// standing. This test unrolls nothing, and it does not inline Foo.
// SPIRV-Tools does all of that work in the optimized test.

// Three items must each have their own debug instruction: Foo, the parameter
// `x` of Foo, and the loop counter `i`. This test finds them by name.
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[X_NAME:%[0-9]+]] = OpString "x"
// CHECK: [[I_NAME:%[0-9]+]] = OpString "i"
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugFunction [[FOO_NAME]]
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

// `i` is real Function-storage memory. A DebugDeclare describes it, binds to
// that memory, and starts it at 0. This test has no DebugValue instruction for
// each copy, because it has no copies. `i` is a real run-time variable.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[I]] %i {{%[a-zA-Z_0-9]+}}
// CHECK: OpStore %i %uint_0

// The loop survives, and the Unroll loop control bit carries the unroll request
// with it. That bit is the whole reason the optimized test can unroll.
// SPIRV-Tools unrolls loops that carry the bit only. If a compiler drops the
// bit here, no consumer can satisfy the request.
// CHECK: OpLoopMerge {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} Unroll

// The loop condition is a real run-time comparison against a real load of `i`.
// glslang puts this comparison after OpLoopMerge, in its own block.
// CHECK: [[COND_I:%[0-9]+]] = OpLoad %uint %i
// CHECK: {{%[0-9]+}} = OpULessThan %bool [[COND_I]] %uint_2

// The shader has one loop body. Inside it, real loads of `i` index both the
// destination and the source. Neither index is a constant.
//
// glslang loads `i` for the destination index first, then for the source index.
// Each access chain must use its own load. The buffer blocks have no names, so
// this test pins the chains through those index operands, and not by a block
// name.
// CHECK: [[IDX_OUT:%[0-9]+]] = OpLoad %uint %i
// CHECK: [[IDX_IN:%[0-9]+]] = OpLoad %uint %i
// CHECK: [[IN:%[0-9]+]] = OpAccessChain {{.*}} [[IDX_IN]]
// CHECK: [[VAL:%[0-9]+]] = OpLoad %uint [[IN]]
// CHECK: OpStore %param [[VAL]]
// CHECK: [[CALL:%[0-9]+]] = OpFunctionCall %uint %Foo_u1_ %param
// CHECK: [[OUT:%[0-9]+]] = OpAccessChain {{.*}} [[IDX_OUT]]
// CHECK: OpStore [[OUT]] [[CALL]]

// The shader increments the loop counter at run time.
// CHECK: [[PREV:%[0-9]+]] = OpLoad %uint %i
// CHECK: [[NEXT:%[0-9]+]] = OpIAdd %uint [[PREV]]
// CHECK: OpStore %i [[NEXT]]

// The parameter of Foo is real Function-storage memory, and its own
// DebugDeclare describes it. The real computation of Foo runs inside Foo.
// CHECK: %x = OpFunctionParameter {{.*}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare [[X]] %x {{%[a-zA-Z_0-9]+}}
// CHECK: [[FOO_X:%[0-9]+]] = OpLoad %uint %x
// CHECK: [[FOO_RESULT:%[0-9]+]] = OpIMul %uint [[FOO_X]]
// CHECK: OpReturnValue [[FOO_RESULT]]

#version 450
#extension GL_EXT_control_flow_attributes : require
layout(set = 0, binding = 0, std430) readonly buffer Buffer0 { uint buffer0[]; };
layout(set = 0, binding = 1, std430) buffer Result { uint result[]; };

uint Foo(uint x) {
    return x * 2;
}

void main() {
    [[unroll]]
    for (uint i = 0; i < 2; i++) {
        result[i] = Foo(buffer0[i]);
    }
}
