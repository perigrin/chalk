# ABOUTME: A has_default field with no default_value node is an ill-formed MOP; the backend must die loudly, not default to 0.
# ABOUTME: Guards against the 2c-recon footgun where a malformed IR silently read as a compiler miscompile (zhi 019f378f).

use 5.42.0;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
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
return %result
IR

subtest 'a has_default field with no default_value node dies loudly' => sub {
    my ($rn, $mop) = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_malformed);
    my $err = dies {
        Chalk::Target::LLVM->lower($rn, (defined $mop ? (mop => $mop) : ()));
    };
    like($err, qr/has_default.*no default value node|ill-formed MOP/i,
        'ill-formed has_default MOP is refused loudly, not silently defaulted to 0')
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
return %result
IR

subtest 'a well-formed has_default field still lowers' => sub {
    my ($rn, $mop) = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_wellformed);
    my $ll = eval { Chalk::Target::LLVM->lower($rn, (defined $mop ? (mop => $mop) : ())) };
    ok(defined $ll && !$@, 'well-formed has_default lowers without error') or diag($@);
};

done_testing();
