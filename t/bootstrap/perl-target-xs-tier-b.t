# ABOUTME: Tests Perl IR to XS compilation for Tier B files.
# ABOUTME: Compiles generated XS, loads module, and validates behavioral equivalence.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

# === Skip guards ===

my $have_compiler;
eval {
    require ExtUtils::CBuilder;
    $have_compiler = ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
};
unless ($have_compiler) {
    plan skip_all => 'No C compiler available';
}

eval { require Module::Build; 1 }
    or plan skip_all => 'Module::Build not installed';

use TestXSHelpers qw(setup_xs_grammar parse_file_ir build_and_load);

# Build Perl grammar pipeline
my $gen_grammar = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSTierBTest') };
ok(defined $gen_grammar, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

# ============================================================
# 1. Constant.pm — 2 field readers + method
# ============================================================

{
    my $ir = parse_file_ir($gen_grammar, 'lib/Chalk/Bootstrap/IR/Node/Constant.pm');
    ok(defined $ir, 'Constant: parse produces IR');

    SKIP: {
        skip 'Constant: no IR', 8 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierB::Constant';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'Constant: XS builds') or do {
            diag $err;
            skip 'Constant: build failed', 6;
        };

        skip 'Constant: inherits from IR::Node with required params - XS wrapper param forwarding not yet implemented', 6;
    }
}

# ============================================================
# 2. XS::AST::Node.pm — method with die (same as Tier A pattern)
# ============================================================

{
    my $ir = parse_file_ir($gen_grammar, 'lib/Chalk/Bootstrap/Target/XS/AST/Node.pm');
    ok(defined $ir, 'XS::AST::Node: parse produces IR');

    SKIP: {
        skip 'XS::AST::Node: no IR', 3 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierB::Node';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'Node: XS builds') or do {
            diag $err;
            skip 'Node: build failed', 1;
        };

        my $obj = eval { $module->new() };
        is($@, '', 'Node: new() succeeds');

        eval { $obj->emit() };
        like($@, qr/Subclass must implement emit/,
            'Node: emit() dies with expected message');
    }
}

# ============================================================
# 3. XS::AST::Statement.pm — 1 field reader + interpolated emit
# ============================================================

{
    my $ir = parse_file_ir($gen_grammar, 'lib/Chalk/Bootstrap/Target/XS/AST/Statement.pm');
    ok(defined $ir, 'Statement: parse produces IR');

    SKIP: {
        skip 'Statement: no IR', 5 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierB::Statement';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'Statement: XS builds') or do {
            diag $err;
            skip 'Statement: build failed', 3;
        };

        my $obj = eval { $module->new(code => 'RETVAL = sv;') };
        is($@, '', 'Statement: new() succeeds');

        is($obj->code(), 'RETVAL = sv;', 'Statement: code reader');
        is($obj->emit(), "    RETVAL = sv;\n", 'Statement: emit() interpolates correctly');
    }
}

# ============================================================
# 4. XS::AST::Module.pm — 2 field readers + 2-var interpolated emit
# ============================================================

{
    my $ir = parse_file_ir($gen_grammar, 'lib/Chalk/Bootstrap/Target/XS/AST/Module.pm');
    ok(defined $ir, 'Module: parse produces IR');

    SKIP: {
        skip 'Module: no IR', 6 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierB::Module';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'Module: XS builds') or do {
            diag $err;
            skip 'Module: build failed', 4;
        };

        my $obj = eval { $module->new(module => 'Foo', package => 'Foo') };
        is($@, '', 'Module: new() succeeds');

        is($obj->module(), 'Foo', 'Module: module reader');
        is($obj->package(), 'Foo', 'Module: package reader');
        is($obj->emit(), "MODULE = Foo  PACKAGE = Foo\n\n",
            'Module: emit() interpolates 2 variables correctly');
    }
}

# ============================================================
# 5. Constructor.pm — 1 field reader + method
# ============================================================

{
    my $ir = parse_file_ir($gen_grammar, 'lib/Chalk/Bootstrap/IR/Node/Constructor.pm');
    ok(defined $ir, 'Constructor: parse produces IR');

    SKIP: {
        skip 'Constructor: no IR', 4 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierB::Constructor';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'Constructor: XS builds') or do {
            diag $err;
            skip 'Constructor: build failed', 2;
        };

        skip 'Constructor: inherits from IR::Node with required params - XS wrapper param forwarding not yet implemented', 2;
    }
}

done_testing();
