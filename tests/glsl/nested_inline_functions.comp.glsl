// RUN: %glslang

// This shader is a GLSL restatement of
// nested_inline_functions_optimized.comp.glsl. main calls Bar, and Bar calls
// Foo.
//
// The glslang default never inlines (see CLAUDE.md). Foo and Bar both stay
// real, separate functions. glslang inlines neither one into the other.

// Foo has its own DebugFunction. This test asserts this fact for one reason
// only: to anchor the guard below. The guard needs a declaration assertion
// above it, and a body assertion beneath it. Its region then covers the span
// where the compiler declares a DebugInlinedAt.
// CHECK: [[FOO_DECL_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugFunction [[FOO_DECL_NAME]]

// The debug information does not describe the call as an inlined call.
//
// Keep this guard in place, between a declaration assertion and a body
// assertion. A CHECK-NOT directive searches only the span between the two
// matches around it. The compiler declares DebugInlinedAt in the module
// preamble. At the end of the file, this guard matches nothing and always
// passes.
// CHECK-NOT: {{DebugInlinedAt}}

// The shader loads `a` from the buffer one time, into real memory. glslang
// passes function arguments by pointer to real Function-storage memory.
//
// main reloads the real value of `a` and stores it into a real argument slot.
// It then calls Bar through that slot. The real value that the call returns
// reaches result[0].
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare {{%[a-zA-Z_0-9]+}} %a {{%[a-zA-Z_0-9]+}}
// CHECK: [[A:%[0-9]+]] = OpLoad %uint %a
// CHECK: OpStore %param_0 [[A]]
// CHECK: [[BAR_CALL:%[0-9]+]] = OpFunctionCall %uint %Bar_u1_ %param_0
// CHECK: OpStore {{%[0-9]+}} [[BAR_CALL]]

// The parameter of Foo is real Function-storage memory. A DebugDeclare
// instruction must describe this parameter, and bind it to this real
// memory.
//
// Inside Foo, a real OpLoad instruction reads the parameter. A real OpIMul
// instruction then computes the result from that value, and Foo returns it.
// CHECK: %x = OpFunctionParameter {{.*}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare {{%[a-zA-Z_0-9]+}} %x {{%[a-zA-Z_0-9]+}}
// CHECK: [[X:%[0-9]+]] = OpLoad %uint %x
// CHECK: [[FOO_RESULT:%[0-9]+]] = OpIMul %uint [[X]]
// CHECK: OpReturnValue [[FOO_RESULT]]

// The parameter of Bar is also real Function-storage memory. Its own
// DebugDeclare instruction describes it.
//
// Bar reloads the real value of this parameter and stores it into its own
// argument slot. It then calls Foo through that slot. The real value that Foo
// returns feeds the computation of Bar and the return value of Bar.
// CHECK: %y = OpFunctionParameter {{.*}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare {{%[a-zA-Z_0-9]+}} %y {{%[a-zA-Z_0-9]+}}
// CHECK: [[Y:%[0-9]+]] = OpLoad %uint %y
// CHECK: OpStore %param [[Y]]
// CHECK: [[FOO_CALL:%[0-9]+]] = OpFunctionCall %uint %Foo_u1_ %param
// CHECK: [[BAR_RESULT:%[0-9]+]] = OpIAdd %uint [[FOO_CALL]]
// CHECK: OpReturnValue [[BAR_RESULT]]

#version 450
layout(set = 0, binding = 0, std430) readonly buffer Buffer0 { uint buffer0[]; };
layout(set = 0, binding = 1, std430) buffer Result { uint result[]; };

uint Foo(uint x) {
    return x * 2;
}

uint Bar(uint y) {
    return Foo(y) + 1;
}

void main() {
    uint a = buffer0[0];
    result[0] = Bar(a);
}
