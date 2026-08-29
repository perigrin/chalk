# ABOUTME: An indirect method call is emitted at the callee's DEFINED ABI type,
# ABOUTME: even when the call site's node has since narrowed to a subtype.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::Target::LLVM ();

# A method is DEFINED once, at one LLVM return type, and the vtable holds a
# bitcast of that one function pointer. The call site must therefore call it at
# the type it was DEFINED at -- not at whatever type the call's own node has
# been narrowed to.
#
# This is what makes site 2 a DIFFERENT defect from the field-store guard, even
# though both surfaced as `ne`-blindness after `Scalar` became refinable:
#
#   FIELD STORE -- the payload cell is one i64 either way, so Int-into-Scalar
#                  is coherent and the guard was simply wrong to refuse it.
#   METHOD CALL -- `Scalar` is `%Slot (i8*)` and `Int` is `i64 (i8*)`. These
#                  are different machine types. Calling an i64-returning
#                  function through a %Slot-returning pointer is UB, so the
#                  refinement must NOT be allowed to change the call's ABI.
#
# Hence: relax the field guard, but keep this one -- and make the call follow
# the ABI rather than the node.

my $ret_ty = \&Chalk::Target::LLVM::_method_fn_llvm_ret_type;
my $ptr_ty = \&Chalk::Target::LLVM::Context::_method_fn_type;

subtest 'the two type authorities agree on every supported repr' => sub {
    # _method_fn_type names the FUNCTION POINTER type the call is bitcast
    # through; _method_fn_llvm_ret_type names the RETURN type the call
    # instruction is emitted at. _lower_call_method's comment asserts that they
    # "can never disagree" because both derive from one authority.
    #
    # They did disagree, at exactly one repr. `Scalar` was given a pointer type
    # (`%Slot (i8*)`) when Scalar became a legal method return, and the return
    # arm was not added alongside it -- so a Scalar-returning method could be
    # POINTED AT but not CALLED. Nothing caught it because the ABI equality
    # check upstream rejected the Scalar/Int pair before either was reached.
    for my $repr (qw(Int Num Str Boolean Undef Scalar)) {
        my $ptr = eval { $ptr_ty->($repr) };
        my $ret = eval { $ret_ty->($repr) };
        ok(defined $ptr && defined $ret,
           "$repr has BOTH a pointer type and a return type")
            or next;
        is($ptr, "$ret (i8*)",
           "$repr: the pointer type is the return type applied to (i8*)");
    }
};

subtest 'Scalar and Int are DIFFERENT machine types' => sub {
    # The premise the whole distinction rests on. If these were the same, the
    # refinement would be free and this site could be relaxed like the field
    # store was.
    isnt($ret_ty->('Scalar'), $ret_ty->('Int'),
         'a Scalar-returning method and an Int-returning one do not share a type');
    is($ret_ty->('Scalar'), '%Slot', 'Scalar returns the uniform cell');
    is($ret_ty->('Int'),    'i64',   'Int returns a bare machine word');
};

done_testing;
