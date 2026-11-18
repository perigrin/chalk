# ABOUTME: A has_default field with no default_value node is an ill-formed MOP; the backend must die loudly, not default to 0.
# ABOUTME: Guards against the 2c-recon footgun where a malformed IR silently read as a compiler miscompile (zhi 019f378f).

use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;

use Chalk::CodeGen::Harness::Rooted qw(rooted);
require Chalk::CodeGen::Harness::MdtestCorpus;
require Chalk::Target::LLVM;

# A class whose field 'a' is declared has_default: true but supplies NO
# default_value node. This is ill-formed -- has_default promises a default value
# node. The backend must refuse loudly rather than silently store 0 (which reads
# at runtime identically to a real default of 0, so a malformed test/corpus IR
# would look like a miscompile).
my $ir_malformed = <<'IR';
%cls    = MOP::Class(name: "Bad")
%mf_a   = MOP::Field(class: %cls, name: "a", fieldix: 0, param: false, reader: false, has_default: true, type: "Int")
%fa_a   = FieldAccess(field_index: 0, field_stash: "Bad") :Int
%mi     = MOP::Method(class: %cls, name: "a", body: %fa_a, return_repr: "Int")
%new_o  = Call(dispatch_kind: "method", name: "new", class: "Bad") :Object
%result = Call(%new_o, dispatch_kind: "method", name: "a", class: "Bad") :Int
%s      = Coerce(%result : Int -> Str) :Str
%p      = Print(%s)
return %p
control: %new_o -> %p
IR

subtest 'a has_default field with no default_value node dies loudly' => sub {
    my ($rn, $mop) = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_malformed);
    my $err = dies {
        Chalk::Target::LLVM->lower(rooted($rn, $mop), (defined $mop ? (mop => $mop) : ()));
    };
    like($err, qr/GAP: T2: out of its slices \(\Qa field default that is not made of itself\E\)/,
        'ill-formed has_default MOP is refused by T2\'s reason, not silently defaulted to 0')
        or diag($err // '(no error -- lowered silently)');
};

# A WELL-FORMED has_default field (with a default_value node) still lowers.
my $ir_wellformed = <<'IR';
%cls    = MOP::Class(name: "Good")
%c5     = Constant(5) :Int
%mf_a   = MOP::Field(class: %cls, name: "a", fieldix: 0, param: false, reader: false, has_default: true, default_value: %c5, type: "Int")
%fa_a   = FieldAccess(field_index: 0, field_stash: "Good") :Int
%mi     = MOP::Method(class: %cls, name: "a", body: %fa_a, return_repr: "Int")
%new_o  = Call(dispatch_kind: "method", name: "new", class: "Good") :Object
%result = Call(%new_o, dispatch_kind: "method", name: "a", class: "Good") :Int
%s      = Coerce(%result : Int -> Str) :Str
%p      = Print(%s)
return %p
control: %new_o -> %p
IR

subtest 'a well-formed has_default field still lowers' => sub {
    my ($rn, $mop) = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_wellformed);
    my $ll = eval { Chalk::Target::LLVM->lower(rooted($rn, $mop), (defined $mop ? (mop => $mop) : ())) };
    ok(defined $ll && !$@, 'well-formed has_default lowers without error') or diag($@);
    my $lli = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
    SKIP: {
        skip "no lli at $lli", 1 unless -x $lli && defined $ll;
        require File::Temp;
        my ($fh, $path) = File::Temp::tempfile(SUFFIX => '.ll', UNLINK => 1);
        print $fh $ll; close $fh;
        is(scalar qx($lli $path 2>&1), '5', 'and prints its default, 5');
    }
};

done_testing();
