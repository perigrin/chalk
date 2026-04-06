# ABOUTME: Tests Perl::Actions semantic actions for Tier A files.
# ABOUTME: Parses 4 pure data class .pm files and validates IR structure.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use Chalk::IR::UseInfo;

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;

# Build Perl grammar pipeline: IR → generated Perl → eval → grammar objects
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ActionsTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::ActionsTest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

# === Helper to parse a file and extract Perl IR ===

my sub parse_file($file) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    local $/;
    my $source = <$fh>;

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    return undef unless defined $result;

    # Extract SemanticAction value (index 4 in 5-ary composite)
    my $sem_ctx = $result->[4];
    return undef unless defined $sem_ctx;
    return $sem_ctx->extract();
}

# === Helper to validate Constructor node ===

my sub is_constructor($node, $expected_class, $msg) {
    ok(defined $node, "$msg: defined");
    return unless defined $node;
    is($node->operation(), 'Constructor', "$msg: is Constructor");
    is($node->class(), $expected_class, "$msg: class is $expected_class");
}

my sub is_constant($node, $expected_value, $msg) {
    ok(defined $node, "$msg: defined");
    return unless defined $node;
    is($node->operation(), 'Constant', "$msg: is Constant");
    is($node->value(), $expected_value, "$msg: value is '$expected_value'");
}

my sub is_use_info($node, $expected_name, $msg) {
    ok(defined $node, "$msg: defined");
    return unless defined $node;
    ok($node isa Chalk::IR::UseInfo, "$msg: is UseInfo");
    is($node->name(), $expected_name, "$msg: name is '$expected_name'");
}

# ============================================================
# 1. Start.pm — class :isa, method returning string
# ============================================================

{
    my $ir = parse_file('lib/Chalk/Bootstrap/IR/Node/Start.pm');
    ok(defined $ir, 'Start.pm: parse produces IR');

    SKIP: {
        skip 'Start.pm: no IR', 20 unless defined $ir;

        is_constructor($ir, 'Program', 'Start.pm Program');
        my $stmts = $ir->inputs()->[0];
        is(ref $stmts, 'ARRAY', 'Start.pm: statements is arrayref');

        # Expect: use 5.42.0; use utf8; use experimental 'class'; class ... { ... }
        # The exact count depends on how many statements parse through
        cmp_ok(scalar $stmts->@*, '>=', 4, 'Start.pm: at least 4 statements');

        # First statement: use 5.42.0
        my $use_ver = $stmts->[0];
        is_use_info($use_ver, '5.42.0', 'Start.pm use 5.42.0');

        # Second: use utf8
        my $use_utf8 = $stmts->[1];
        is_use_info($use_utf8, 'utf8', 'Start.pm use utf8');

        # Third: use experimental 'class'
        my $use_exp = $stmts->[2];
        is_use_info($use_exp, 'experimental', 'Start.pm use experimental');

        # Last: ClassDecl
        my $cls = $stmts->[-1];
        is_constructor($cls, 'ClassDecl', 'Start.pm ClassDecl');
        is_constant($cls->inputs()->[0],
            'Chalk::Bootstrap::IR::Node::Start', 'Start.pm class name');
        is_constant($cls->inputs()->[1],
            'Chalk::Bootstrap::IR::Node', 'Start.pm parent class');

        # Class body has 1 method
        my $body = $cls->inputs()->[2];
        is(ref $body, 'ARRAY', 'Start.pm: class body is arrayref');
        is(scalar $body->@*, 1, 'Start.pm: class body has 1 method');

        my $meth = $body->[0];
        is_constructor($meth, 'MethodDecl', 'Start.pm method');
        is_constant($meth->inputs()->[0], 'operation', 'Start.pm method name');

        # Method body has ReturnStmt
        my $meth_body = $meth->inputs()->[2];
        is(ref $meth_body, 'ARRAY', 'Start.pm: method body is arrayref');
        is(scalar $meth_body->@*, 1, 'Start.pm: method body has 1 statement');

        my $ret = $meth_body->[0];
        is_constructor($ret, 'ReturnStmt', 'Start.pm return');
        is_constant($ret->inputs()->[0], 'Start', 'Start.pm return value');
    }
}

# ============================================================
# 2. Return.pm — class :isa, method returning string
# ============================================================

{
    my $ir = parse_file('lib/Chalk/Bootstrap/IR/Node/Return.pm');
    ok(defined $ir, 'Return.pm: parse produces IR');

    SKIP: {
        skip 'Return.pm: no IR', 10 unless defined $ir;

        is_constructor($ir, 'Program', 'Return.pm Program');
        my $stmts = $ir->inputs()->[0];
        my $cls = $stmts->[-1];
        is_constructor($cls, 'ClassDecl', 'Return.pm ClassDecl');
        is_constant($cls->inputs()->[0],
            'Chalk::Bootstrap::IR::Node::Return', 'Return.pm class name');
        is_constant($cls->inputs()->[1],
            'Chalk::Bootstrap::IR::Node', 'Return.pm parent class');

        my $body = $cls->inputs()->[2];
        is(scalar $body->@*, 1, 'Return.pm: class body has 1 method');
        my $meth = $body->[0];
        is_constant($meth->inputs()->[0], 'operation', 'Return.pm method name');

        my $ret = $meth->inputs()->[2][0];
        is_constructor($ret, 'ReturnStmt', 'Return.pm return');
        is_constant($ret->inputs()->[0], 'Return', 'Return.pm return value');
    }
}

# ============================================================
# 3. Target.pm — class, 2 methods with param, die
# ============================================================

{
    my $ir = parse_file('lib/Chalk/Bootstrap/Target.pm');
    ok(defined $ir, 'Target.pm: parse produces IR');

    SKIP: {
        skip 'Target.pm: no IR', 15 unless defined $ir;

        is_constructor($ir, 'Program', 'Target.pm Program');
        my $stmts = $ir->inputs()->[0];
        my $cls = $stmts->[-1];
        is_constructor($cls, 'ClassDecl', 'Target.pm ClassDecl');
        is_constant($cls->inputs()->[0],
            'Chalk::Bootstrap::Target', 'Target.pm class name');
        is($cls->inputs()->[1], undef, 'Target.pm: no parent class');

        my $body = $cls->inputs()->[2];
        is(scalar $body->@*, 2, 'Target.pm: class body has 2 methods');

        # First method: generate($ir)
        my $m1 = $body->[0];
        is_constructor($m1, 'MethodDecl', 'Target.pm generate method');
        is_constant($m1->inputs()->[0], 'generate', 'Target.pm generate name');
        my $m1_params = $m1->inputs()->[1];
        is(scalar $m1_params->@*, 1, 'Target.pm generate has 1 param');

        # Body has DieCall
        my $m1_body = $m1->inputs()->[2];
        is(scalar $m1_body->@*, 1, 'Target.pm generate body has 1 statement');
        is_constructor($m1_body->[0], 'DieCall', 'Target.pm generate dies');

        # Second method: generate_distribution($ir)
        my $m2 = $body->[1];
        is_constructor($m2, 'MethodDecl', 'Target.pm generate_distribution method');
        is_constant($m2->inputs()->[0], 'generate_distribution',
            'Target.pm generate_distribution name');
    }
}

# ============================================================
# 4. Pass.pm — class, 2 methods (0/1 param), die
# ============================================================

{
    my $ir = parse_file('lib/Chalk/Bootstrap/Optimizer/Pass.pm');
    ok(defined $ir, 'Pass.pm: parse produces IR');

    SKIP: {
        skip 'Pass.pm: no IR', 15 unless defined $ir;

        is_constructor($ir, 'Program', 'Pass.pm Program');
        my $stmts = $ir->inputs()->[0];
        my $cls = $stmts->[-1];
        is_constructor($cls, 'ClassDecl', 'Pass.pm ClassDecl');
        is_constant($cls->inputs()->[0],
            'Chalk::Bootstrap::Optimizer::Pass', 'Pass.pm class name');
        is($cls->inputs()->[1], undef, 'Pass.pm: no parent class');

        my $body = $cls->inputs()->[2];
        is(scalar $body->@*, 2, 'Pass.pm: class body has 2 methods');

        # First method: name() - no params
        my $m1 = $body->[0];
        is_constructor($m1, 'MethodDecl', 'Pass.pm name method');
        is_constant($m1->inputs()->[0], 'name', 'Pass.pm name method name');
        is(scalar $m1->inputs()->[1]->@*, 0, 'Pass.pm name has 0 params');

        # Second method: run($ir) - 1 param
        my $m2 = $body->[1];
        is_constructor($m2, 'MethodDecl', 'Pass.pm run method');
        is_constant($m2->inputs()->[0], 'run', 'Pass.pm run method name');
        is(scalar $m2->inputs()->[1]->@*, 1, 'Pass.pm run has 1 param');
    }
}

done_testing();
