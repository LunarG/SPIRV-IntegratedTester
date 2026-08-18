// RUN: %glslang

// This shader is a GLSL restatement of
// two_functions_inlined_optimized.comp.glsl. main calls two different
// functions, Foo and Bar, one time each.
//
// The glslang default never inlines (see CLAUDE.md). Foo and Bar both stay
// real, separate functions, and glslang inlines neither one.

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
// It then calls Foo through that slot. The real value that Foo returns reaches
// result[0].
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare {{%[a-zA-Z_0-9]+}} %a {{%[a-zA-Z_0-9]+}}
// CHECK: [[A:%[0-9]+]] = OpLoad %uint %a
// CHECK: OpStore %param [[A]]
// CHECK: [[FOO_CALL:%[0-9]+]] = OpFunctionCall %uint %Foo_u1_ %param
// CHECK: OpStore {{%[0-9]+}} [[FOO_CALL]]

// main reloads `a` a second time and stores it into a separate real argument
// slot. It then calls Bar through that slot. The real value that Bar returns
// reaches result[1].
// CHECK: [[A_RELOAD:%[0-9]+]] = OpLoad %uint %a
// CHECK: OpStore %param_0 [[A_RELOAD]]
// CHECK: [[BAR_CALL:%[0-9]+]] = OpFunctionCall %uint %Bar_u1_ %param_0
// CHECK: OpStore {{%[0-9]+}} [[BAR_CALL]]

// The parameter of Foo is real Function-storage memory. A DebugDeclare
// instruction describes it. The computation of Foo runs here and multiplies by
// two, and Foo returns the result.
// CHECK: %x = OpFunctionParameter {{.*}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare {{%[a-zA-Z_0-9]+}} %x {{%[a-zA-Z_0-9]+}}
// CHECK: [[X:%[0-9]+]] = OpLoad %uint %x
// CHECK: [[FOO_RESULT:%[0-9]+]] = OpIMul %uint [[X]]
// CHECK: OpReturnValue [[FOO_RESULT]]

// The parameter of Bar is also real Function-storage memory. Its own
// DebugDeclare instruction describes it. The computation of Bar runs here and
// adds 100, and Bar returns the result.
// CHECK: %y = OpFunctionParameter {{.*}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare {{%[a-zA-Z_0-9]+}} %y {{%[a-zA-Z_0-9]+}}
// CHECK: [[Y:%[0-9]+]] = OpLoad %uint %y
// CHECK: [[BAR_RESULT:%[0-9]+]] = OpIAdd %uint [[Y]]
// CHECK: OpReturnValue [[BAR_RESULT]]

#version 450
layout(set = 0, binding = 0, std430) readonly buffer Buffer0 { uint buffer0[]; };
layout(set = 0, binding = 1, std430) buffer Result { uint result[]; };

uint Foo(uint x) {
    return x * 2;
}

uint Bar(uint y) {
    return y + 100;
}

void main() {
    uint a = buffer0[0];
    result[0] = Foo(a);
    result[1] = Bar(a);
}
