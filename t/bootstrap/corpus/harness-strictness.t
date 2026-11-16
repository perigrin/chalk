# ABOUTME: Teeth for MdtestCorpus harness strictness — silent-drop parse paths
# ABOUTME: (bare const_type, dropped MOP positional inputs, dup field_index) croak.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness::MdtestCorpus;
use Chalk::MOP;
use Chalk::Target::LLVM;

my $H = 'Chalk::CodeGen::Harness::MdtestCorpus';

# --- Finding 5a: a bare Constant value with a stray ',' or ':' -----------------
subtest 'bare Constant value with a comma croaks (not a garbage integer)' => sub {
    my $ir = <<'IR';
%c = Constant(1, 2) :Int
return %c
IR
    my $ok = eval { $H->build_graph_from_ir($ir); 1 };
    ok(!$ok, 'a bare value containing a comma does not silently build a Constant');
    like($@, qr/const/i, "croak mentions the const parse: $@");
};

subtest 'bare Constant value with a colon croaks' => sub {
    my $ir = <<'IR';
%c = Constant(const_type: integer) :Int
return %c
IR
    my $ok = eval { $H->build_graph_from_ir($ir); 1 };
    ok(!$ok, 'a bare value containing a colon does not silently build a Constant');
    like($@, qr/const/i, "croak mentions the const parse: $@");
};

subtest 'a clean bare integer Constant still parses' => sub {
    my $ir = <<'IR';
%c = Constant(42) :Int
return %c
IR
    my $g = eval { $H->build_graph_from_ir($ir) };
    ok(defined $g, 'Constant(42) still builds') or diag($@);
};

# --- Finding 5b: MOP::* silently dropping positional inputs / params: ----------
subtest 'MOP::Method with a positional %ref input croaks (input would be dropped)' => sub {
    my $ir = <<'IR';
%c = Constant(1) :Int
%cls = MOP::Class(name: "K")
%m = MOP::Method(%c, class: %cls, name: "m", return_repr: Int)
return %c
IR
    my $ok = eval { $H->build_graph_from_ir($ir); 1 };
    ok(!$ok, 'a positional input on a MOP::* line is not silently dropped');
    like($@, qr/positional|input|drop/i, "croak names the dropped input: $@");
};

subtest 'a clean MOP::Method (no positional input) still parses' => sub {
    my $ir = <<'IR';
%c = Constant(1) :Int
%cls = MOP::Class(name: "K")
%m = MOP::Method(class: %cls, name: "m", body: %c, return_repr: Int)
return %c
IR
    my $g = eval { $H->build_graph_from_ir($ir) };
    ok(defined $g, 'MOP::Method with only kwargs still builds') or diag($@);
};

done_testing;
