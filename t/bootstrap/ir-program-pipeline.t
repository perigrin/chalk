# ABOUTME: Tests that Actions.pm produces Chalk::IR::Program for top-level programs.
# ABOUTME: Verifies end-to-end pipeline: parse source -> Chalk::IR::Program with partitioned metadata.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::IR::Program;
use Chalk::IR::UseInfo;
use Chalk::IR::ClassInfo;
use Chalk::IR::SubInfo;

# Build Perl grammar pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ProgramPipelineTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::ProgramPipelineTest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

my sub parse_file($file) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    local $/;
    my $source = <$fh>;

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    return undef unless defined $result;

    my $sem_ctx = $result;
    return undef unless defined $sem_ctx;
    return $sem_ctx->extract();
}

# ============================================================
# 1. UseInfo.pm — simple class with use decls, one class
#    Verifies Actions produces Chalk::IR::Program (not Constructor:Program)
# ============================================================

{
    my $ir = parse_file('lib/Chalk/IR/UseInfo.pm');
    ok(defined $ir, 'UseInfo.pm: parse produces IR');

    SKIP: {
        skip 'UseInfo.pm: no IR', 12 unless defined $ir;

        # Top-level result is Chalk::IR::Program, not Constructor:Program
        isa_ok($ir, 'Chalk::IR::Program',
            'UseInfo.pm: top-level IR is Chalk::IR::Program (not Constructor)');

        # use_decls contains UseInfo objects
        my $use_decls = $ir->use_decls();
        is(ref $use_decls, 'ARRAY', 'Program use_decls() is arrayref');
        ok(scalar $use_decls->@* >= 1, 'Program has at least 1 use_decl')
            or diag("Got " . scalar $use_decls->@* . " use_decls");

        if (scalar $use_decls->@* >= 1) {
            isa_ok($use_decls->[0], 'Chalk::IR::UseInfo', 'use_decls[0] is UseInfo');
        }

        # classes contains ClassInfo objects
        my $classes = $ir->classes();
        is(ref $classes, 'ARRAY', 'Program classes() is arrayref');
        ok(scalar $classes->@* >= 1, 'Program has at least 1 class')
            or diag("Got " . scalar $classes->@* . " classes");

        if (scalar $classes->@* >= 1) {
            isa_ok($classes->[0], 'Chalk::IR::ClassInfo', 'classes[0] is ClassInfo');
            is($classes->[0]->name(), 'Chalk::IR::UseInfo',
                'UseInfo.pm class name is Chalk::IR::UseInfo');
        }

        # top_level_subs — UseInfo.pm has no top-level subs
        my $top_subs = $ir->top_level_subs();
        is(ref $top_subs, 'ARRAY', 'Program top_level_subs() is arrayref');

        # Program no longer exposes inputs() — it is not a Constructor node
        ok(!$ir->can('inputs'), 'Chalk::IR::Program does not have inputs() method')
            or diag("Unexpected: Program has inputs() method — it should not be a Constructor node");
    }
}

# ============================================================
# 2. Shim.pm — package (not class) with top-level subs
#    Verifies top_level_subs is populated; use_decls captured; no classes
# ============================================================

{
    my $ir = parse_file('lib/Chalk/IR/Shim.pm');
    ok(defined $ir, 'Shim.pm: parse produces IR');

    SKIP: {
        skip 'Shim.pm: no IR', 5 unless defined $ir;

        isa_ok($ir, 'Chalk::IR::Program', 'Shim.pm: top-level IR is Chalk::IR::Program');

        my $use_decls = $ir->use_decls();
        ok(scalar $use_decls->@* >= 1, 'Shim.pm: has use_decls');

        # Shim.pm uses 'package' not 'class', so no ClassInfo entries
        my $classes = $ir->classes();
        is(scalar $classes->@*, 0, 'Shim.pm: no classes (uses package not class syntax)');

        # top_level_subs — check the accessor works
        my $top_subs = $ir->top_level_subs();
        is(ref $top_subs, 'ARRAY', 'Shim.pm: top_level_subs() is arrayref');
    }
}

# ============================================================
# 3. Constant.pm — class with multiple fields and methods
#    Verifies partitioning works for a richer class
# ============================================================

{
    my $ir = parse_file('lib/Chalk/IR/Node/Constant.pm');
    ok(defined $ir, 'Constant.pm: parse produces IR');

    SKIP: {
        skip 'Constant.pm: no IR', 7 unless defined $ir;

        isa_ok($ir, 'Chalk::IR::Program', 'Constant.pm: top-level IR is Chalk::IR::Program');

        # All use_decls are UseInfo
        my $use_decls = $ir->use_decls();
        for my $ud ($use_decls->@*) {
            isa_ok($ud, 'Chalk::IR::UseInfo', "use_decl '${\$ud->name()}' is UseInfo");
        }

        # All classes are ClassInfo
        my $classes = $ir->classes();
        ok(scalar $classes->@* >= 1, 'Constant.pm: has at least 1 class');
        for my $cls ($classes->@*) {
            isa_ok($cls, 'Chalk::IR::ClassInfo', "class '${\$cls->name()}' is ClassInfo");
        }
    }
}

done_testing();
