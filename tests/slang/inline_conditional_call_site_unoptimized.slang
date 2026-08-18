// RUN: %slangc -O0

// This test is the counterpart to inline_conditional_call_site.slang, with no
// inlining. The -O0 flag disables the Slang optimizer. Foo therefore stays a
// real, separate function, and both call sites stay real OpFunctionCall
// instructions.
//
// No compiler moves anything across a function boundary, so no inline record
// can be wrong. The shape of the conditional is the purpose of this variant.
//
// Slang emits no DebugLexicalBlock at any optimization level, so it gives
// neither arm a scope of its own. glslang and dxc both do. The scope stays the
// DebugFunction of computeMain across the whole if statement. `b` and `c` are
// parented to that scope, even though the shader declares them inside the
// arms.
//
// That shape is conformant, because the enclosing function is a lexical scope
// that contains those lines. It is also what makes the DebugInlinedAt of the
// inlined variant name computeMain, and not an arm. This test pins that shape,
// so that a later change to it is visible here.
//
// The line table must still be right for each arm. The debug information must
// report each call on the statement that holds it. This test takes those lines
// from the declaration of `b` and of `c`, so it needs no absolute line
// numbers.

// These assertions capture the name strings. Slang emits the caller's strings before the callee's, and
// interleaves `b` and `c` around them.
// CHECK: [[MAIN_NAME:%[0-9]+]] = OpString "computeMain"
// CHECK: [[A_NAME:%[0-9]+]] = OpString "a"
// CHECK: [[B_NAME:%[0-9]+]] = OpString "b"
// CHECK: [[FOO_NAME:%[0-9]+]] = OpString "Foo"
// CHECK: [[X_NAME:%[0-9]+]] = OpString "x"
// CHECK: [[C_NAME:%[0-9]+]] = OpString "c"

// These assertions cover the caller and its locals. All three are parented to
// the DebugFunction of computeMain. `a` comes from outside the if statement, and
// `b` comes from inside the if arm. The line that declares `b` is the call line
// of that arm.
// CHECK: [[MAIN:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[MAIN_NAME]]
// CHECK: %a = OpExtInst {{.*}} DebugLocalVariable [[A_NAME]] {{.*}} [[MAIN]] {{.*}}
// CHECK: %b = OpExtInst {{.*}} DebugLocalVariable [[B_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[THEN_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} [[MAIN]] {{.*}}

// These assertions cover the callee and its parameter. Slang names the debug
// variable of the parameter %x_0, because %x is the OpFunctionParameter itself.
//
// This test captures the declaration line of Foo, for the line table inside the
// body of Foo far below.
// CHECK: [[FOO:%[0-9]+]] = OpExtInst {{.*}} DebugFunction [[FOO_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[FOO_LINE:%[a-zA-Z_0-9]+]] {{.*}}
// CHECK: %x_0 = OpExtInst {{.*}} DebugLocalVariable [[X_NAME]] {{.*}} [[FOO]] {{.*}}

// This assertion covers the local of the else arm, and with it the call line of
// that arm. This local is also parented to computeMain, and not to an arm.
// CHECK: %c = OpExtInst {{.*}} DebugLocalVariable [[C_NAME]] {{%[a-zA-Z_0-9]+}} {{%[a-zA-Z_0-9]+}} [[ELSE_LINE:%[a-zA-Z_0-9]+]] {{%[a-zA-Z_0-9]+}} [[MAIN]] {{.*}}

// The debug information does not describe the call as an inlined call.
//
// Keep this guard in place, between a declaration assertion and a body
// assertion. A CHECK-NOT directive searches only the span between the two
// matches around it. The compiler declares DebugInlinedAt in the module
// preamble. At the end of the file, this guard matches nothing and always
// passes.
// CHECK-NOT: {{DebugInlinedAt}}

// In the caller, two instructions describe `a`. A DebugDeclare binds to its real
// backing memory, and a DebugValue tracks the loaded value. The shader computes
// the condition from that value.
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugFunctionDefinition [[MAIN]] %computeMain
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare %a %_dbgvar_a {{%[a-zA-Z_0-9]+}}
// CHECK: [[IN:%[0-9]+]] = OpAccessChain {{.*}} %buffer0 %int_0 %int_0
// CHECK: [[VAL:%[0-9]+]] = OpLoad %uint [[IN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %a [[VAL]]
// CHECK: OpStore %_dbgvar_a [[VAL]]
// CHECK: [[COND:%[0-9]+]] = OpUGreaterThan %bool [[VAL]] %uint_10

// This test captures both target labels of the branch. Those captures pin every
// assertion below to the arm that it belongs to.
// CHECK: OpSelectionMerge [[MERGE_LABEL:%[a-zA-Z_0-9]+]] None
// CHECK: OpBranchConditional [[COND]] [[THEN_LABEL:%[a-zA-Z_0-9]+]] [[ELSE_LABEL:%[a-zA-Z_0-9]+]]

// This is the if arm. The scope stays computeMain, because Slang has no scope
// for each arm to enter. The line table must still be on the call statement of
// this arm.
//
// Slang passes the argument by value, so the call takes the loaded value
// directly, and not through an argument slot. Both arms pass the same value.
// CHECK: [[THEN_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[THEN_LINE]] [[THEN_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare %b %_dbgvar_b {{%[a-zA-Z_0-9]+}}
// CHECK: [[THEN_RESULT:%[a-zA-Z_0-9]+]] = OpFunctionCall %uint %Foo [[VAL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %b [[THEN_RESULT]]
// CHECK: OpStore %_dbgvar_b [[THEN_RESULT]]
// CHECK: [[OUT_THEN:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 %int_0
// CHECK: OpStore [[OUT_THEN]] [[THEN_RESULT]]

// This test asserts the else arm in the same way, against its own captures.
// [[ELSE_RESULT]] must be a different id from [[THEN_RESULT]]. The two calls
// are separate calls, even though their arguments are the same.
// CHECK: [[ELSE_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[ELSE_LINE]] [[ELSE_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare %c %_dbgvar_c {{%[a-zA-Z_0-9]+}}
// CHECK: [[ELSE_RESULT:%[a-zA-Z_0-9]+]] = OpFunctionCall %uint %Foo [[VAL]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %c [[ELSE_RESULT]]
// CHECK: OpStore %_dbgvar_c [[ELSE_RESULT]]
// CHECK: [[OUT_ELSE:%[0-9]+]] = OpAccessChain {{.*}} %result %int_0 %int_0
// CHECK: [[SUM:%[0-9]+]] = OpIAdd %uint [[ELSE_RESULT]] %uint_1
// CHECK: OpStore [[OUT_ELSE]] [[SUM]]

// After the if statement, the scope is still the scope of computeMain.
// CHECK: [[MERGE_LABEL]] = OpLabel
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[MAIN]]

// Foo is still a real, separate function with its own scope. Those two calls
// are the only way to reach it. Its parameter arrives by value, and Slang copies
// it into real memory. The debug variable of the parameter binds to that
// memory.
// CHECK: %x = OpFunctionParameter %uint
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugFunctionDefinition [[FOO]] %Foo
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugScope [[FOO]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugLine {{%[a-zA-Z_0-9]+}} [[FOO_LINE]] [[FOO_LINE]]
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugDeclare %x_0 %_dbgvar_x {{%[a-zA-Z_0-9]+}}
// CHECK: {{%[0-9]+}} = OpExtInst {{.*}} DebugValue %x_0 %x
// CHECK: {{%[0-9]+}} = OpIMul %uint %x %uint_2

StructuredBuffer<uint> buffer0;
RWStructuredBuffer<uint> result;

uint Foo(uint x) {
    return x * 2;
}

[shader("compute")]
[numthreads(1,1,1)]
void computeMain(uint3 threadId : SV_DispatchThreadID)
{
    uint a = buffer0[0];
    if (a > 10) {
        uint b = Foo(a);
        result[0] = b;
    } else {
        uint c = Foo(a);
        result[0] = c + 1;
    }
}
