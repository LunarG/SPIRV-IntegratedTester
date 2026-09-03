// RUN: %slangc
// XFAIL: SPIRV-Tools#6718, DebugValue references OpUndef after spirv-opt

// This test is expected to fail today. The assertions below state what the
// tooling must emit. Two of them do not hold yet.
//
// The Slang default runs the SPIRV-Tools optimizer. A pass in that optimizer
// drops the Value operand of two DebugValue instructions and puts a bare
// OpUndef in its place. The correct value exists in the module at both points,
// so no information is lost. Only the reference is wrong.
//
// glslang with spirv-opt emits no OpUndef for this same shader shape, so the
// assertions below describe an achievable result and not a guess. See
// https://github.com/KhronosGroup/SPIRV-Tools/issues/6718.

// A DebugLocalVariable instruction must describe `v` in main, and another must
// describe the parameter `v` of addOne. This test uses a plain float for `v`.
// The result does not depend on the vector type that the other inout test
// uses.
// CHECK: %v = OpExtInst {{.*}} DebugLocalVariable
// CHECK: %v_0 = OpExtInst {{.*}} DebugLocalVariable

// After main loads `v`, the Value operand of DebugValue for `v` is the value
// that main loaded.
// CHECK: [[LOAD:%[0-9]+]] = OpLoad %float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %v [[LOAD]]

// main calls addOne with the value of `v`. The Value operand of DebugValue for
// the parameter of addOne (also named `v`) must be the value that main loaded.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %v_0 [[LOAD]]

// A real OpFAdd instruction adds one to the parameter of addOne. After this
// sum exists, the Value operand of DebugValue for the parameter obeys the
// contract.
// CHECK: [[SUM:%[0-9]+]] = OpFAdd %float
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %v_0 [[SUM]]

// After addOne returns, the Value operand of DebugValue for `v` in main must be
// the sum above. The inout parameter writes that value back to `v`.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %v [[SUM]]

struct SSBO {
    float data;
};

[[vk::binding(1, 0)]]
RWStructuredBuffer<SSBO> ssbo;

void addOne(inout float v) {
    v = v + 1.0;
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main() {
    float v = ssbo[0].data;
    addOne(v);
    ssbo[0].data = v;
}
