# ABOUTME: Scalar is a lowerable stamp -- it has a machine encoding (%Slot),
# ABOUTME: so the loader must carry it through rather than dropping it.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::Serialize::JSON ();
use Chalk::Target::LLVM ();
use Chalk::Target::LLVM::Context ();

# %LOWERABLE_STAMP answers ONE question: can the backend lower this stamp?
# It was written when Scalar had no machine encoding, so Scalar was excluded
# with the ref types. Scalar now encodes as %Slot at both LLVM type
# authorities, and the exclusion outlived its reason -- a method returning an
# un-narrowed Scalar reached the backend with no representation at all and
# GAPped, the largest single group in the corpus gate.
#
# `Unknown` is a DIFFERENT case and must stay excluded: it is the absence of an
# answer, not an answer, and admitting it would let a node claim a machine
# encoding it does not have.

my $is_lowerable = \&Chalk::IR::Serialize::JSON::is_lowerable_stamp;

# The whitelist's members, as the backend sees them. Kept here rather than
# reaching into the module's lexical: the contract is the PREDICATE.
my @CLAIMED = qw(Int Num Str Boolean Undef Object ArrayRef HashRef Array Hash Scalar);

subtest 'every whitelisted stamp has SOME machine encoding' => sub {
    # Deliberately NOT the method-return encoder: that is one narrow consumer,
    # and Object/ArrayRef/HashRef/Array/Hash are lowerable as VALUES while
    # having no method-return form. Lowerability is a claim about the value
    # representation, so _repr_to_llvm_type is the authority to check against.
    my $enc = \&Chalk::Target::LLVM::Context::_repr_to_llvm_type;
    for my $stamp (grep { $is_lowerable->($_) } @CLAIMED) {
        ok(eval { $enc->($stamp); 1 },
           "$stamp is whitelisted AND has a value encoding")
            or diag("whitelisted but unencodable: $@");
    }
};

subtest 'Scalar is lowerable' => sub {
    ok($is_lowerable->('Scalar'), 'Scalar is admitted to the representation field');
    is(Chalk::Target::LLVM::_method_fn_llvm_ret_type('Scalar'), '%Slot',
       'because it encodes as the uniform cell');
};

subtest 'Unknown stays excluded' => sub {
    # The absence of an answer is not an answer. A node still holding Unknown at
    # machine-type selection must GAP, not claim an encoding.
    ok(!$is_lowerable->('Unknown'), 'Unknown is NOT admitted');
    ok(!eval { Chalk::Target::LLVM::_method_fn_llvm_ret_type('Unknown'); 1 },
       'and the backend refuses to encode it');
};

done_testing;
