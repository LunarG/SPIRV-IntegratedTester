// RUN: %slangc
// XFAIL: SPIRV-Tools#6718, DebugValue references OpUndef after spirv-opt

// This test is expected to fail today. The assertions below state what the
// tooling must emit. Four of them do not hold yet.
//
// The Slang default runs the SPIRV-Tools optimizer. A pass in that optimizer
// drops the Value operand of four DebugValue instructions and puts one bare
// OpUndef in the place of each. The correct value exists in the module at all
// four points, so no information is lost. Only the reference is wrong.
//
// This shader has two inout parameters. The defect appears one time for each
// parameter on entry, and one time for each parameter after the call. The
// single-parameter inout tests show the same defect two times.
//
// The single OpUndef also destroys the distinction between `a` and `b`. Both
// parameters name the same value on entry. Both variables in main name that
// same value after the call.
//
// glslang with spirv-opt emits no OpUndef for this same shader shape, and it
// keeps `a` and `b` distinct. So the assertions below describe an achievable
// result and not a guess. See
// https://github.com/KhronosGroup/SPIRV-Tools/issues/6718.

// A DebugLocalVariable instruction must describe each of `a` and `b` in main,
// and another must describe each parameter of addOneToBoth.
// CHECK: %a = OpExtInst {{.*}} DebugLocalVariable
// CHECK: %b = OpExtInst {{.*}} DebugLocalVariable
// CHECK: %b_0 = OpExtInst {{.*}} DebugLocalVariable
// CHECK: %a_0 = OpExtInst {{.*}} DebugLocalVariable

// After main loads `a` and `b`, the Value operand of DebugValue for each
// variable is the value that main loaded for that variable. The two variables
// do not exchange values.
// CHECK: [[LOAD_A:%[0-9]+]] = OpLoad %v4float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %a [[LOAD_A]]
// CHECK: [[LOAD_B:%[0-9]+]] = OpLoad %v4float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %b [[LOAD_B]]

// main calls addOneToBoth with the values of `a` and `b`. The Value operand of
// DebugValue for each parameter must be the value that main loaded for the
// matching variable. The two parameters do not exchange values.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %b_0 [[LOAD_B]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %a_0 [[LOAD_A]]

// A real OpFAdd instruction adds one to each parameter. After these sums
// exist, the Value operand of DebugValue for each parameter obeys the
// contract. The two parameters do not exchange values.
// CHECK: [[SUM_A:%[0-9]+]] = OpFAdd %v4float [[LOAD_A]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %a_0 [[SUM_A]]
// CHECK: [[SUM_B:%[0-9]+]] = OpFAdd %v4float [[LOAD_B]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %b_0 [[SUM_B]]

// After addOneToBoth returns, the Value operand of DebugValue for `a` and for
// `b` in main must be the matching sum above. Each inout parameter writes its
// value back to its own variable.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %b [[SUM_B]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %a [[SUM_A]]

struct SSBO {
    float4 dataA;
    float4 dataB;
};

[[vk::binding(1, 0)]]
RWStructuredBuffer<SSBO> ssbo;

void addOneToBoth(inout float4 a, inout float4 b) {
    a = a + float4(1.0, 1.0, 1.0, 1.0);
    b = b + float4(1.0, 1.0, 1.0, 1.0);
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main() {
    float4 a = ssbo[0].dataA;
    float4 b = ssbo[0].dataB;
    addOneToBoth(a, b);
    ssbo[0].dataA = a;
    ssbo[0].dataB = b;
}
