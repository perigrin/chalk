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

# --- Finding 5c: a duplicate field_index in the registry population ------------
# A minimal class stand-in that yields two DISTINCT fields sharing a fieldix.
# _populate_registry_from_mop_class calls name/parent_name/methods/fields/
# adjust_blocks/subs on the class, so a plain blessed shim exercises the path.
#
# `subs` WAS MISSING AND THE FAILURE NAMED THE WRONG THING: production grew a
# sixth call (LLVM.pm:694, recording sub metadata into the registry rather than
# recovering it by scanning) and this shim was not grown with it, so the test
# died with "Can't locate object method 'subs' via package 'DupClass'" -- which
# reads as a defect in the code under test rather than in the stand-in.
#
# The comment above is the contract, and it is only true if it is MAINTAINED.
# A stub that lists the methods it must provide should be updated in the same
# commit that adds one; that this was not is why the list is now spelled out
# again here.
package DupClass {
    sub new { bless { fields => $_[1] }, $_[0] }
    sub name          { 'Dup' }
    sub parent_name   { undef }
    sub methods       { () }
    sub adjust_blocks { () }
    sub subs          { () }
    sub fields        { @{ $_[0]{fields} } }
}

subtest 'a duplicate field_index croaks (second field would be silently dropped)' => sub {
    my $f0 = Chalk::MOP::Field->new(name => 'a', sigil => '$', class => 'Dup',
                                    fieldix => 0, type => 'Int', attributes => []);
    my $f1 = Chalk::MOP::Field->new(name => 'b', sigil => '$', class => 'Dup',
                                    fieldix => 0, type => 'Int', attributes => []);
    my $cls = DupClass->new([ $f0, $f1 ]);

    my %registry;
    my $ok = eval {
        Chalk::Target::LLVM::_populate_registry_from_mop_class(\%registry, $cls);
        1;
    };
    ok(!$ok, 'a duplicate field_index is not silently dropped');
    like($@, qr/field_index|duplicate|fieldix/i, "croak names the collision: $@");
};

subtest 'two distinct-index fields still populate (no false collision)' => sub {
    my $f0 = Chalk::MOP::Field->new(name => 'a', sigil => '$', class => 'Dup',
                                    fieldix => 0, type => 'Int', attributes => []);
    my $f1 = Chalk::MOP::Field->new(name => 'b', sigil => '$', class => 'Dup',
                                    fieldix => 1, type => 'Int', attributes => []);
    my $cls = DupClass->new([ $f0, $f1 ]);

    my %registry;
    my $ok = eval {
        Chalk::Target::LLVM::_populate_registry_from_mop_class(\%registry, $cls);
        1;
    };
    ok($ok, 'distinct field indices populate without a false collision') or diag($@);
    is(scalar @{ $registry{Dup}{fields} }, 2, 'both fields registered');
};

done_testing;
