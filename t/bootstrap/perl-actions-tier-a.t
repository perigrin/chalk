# ABOUTME: Tests Perl::Actions semantic actions for Tier A files.
# ABOUTME: Parses 4 pure data class .pm files and validates IR structure.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use Chalk::IR::UseInfo;
use Chalk::IR::ClassInfo;
use Chalk::IR::MethodInfo;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Unwind;

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::IR::Program;

# Build Perl grammar pipeline: IR → generated Perl → eval → grammar objects
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
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    local $/;
    my $source = <$fh>;

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    return undef unless defined $result;

    # parse_value returns the unified Context directly after #706
    my $sem_ctx = $result;
    return undef unless defined $sem_ctx;
    return $sem_ctx->extract();
}

# === Helper to validate Constructor node ===

my sub is_constructor($node, $expected_class, $msg) {
    ok(defined $node, "$msg: defined");
    return unless defined $node;
    if ($node isa Chalk::IR::Program) {
        is($expected_class, 'Program', "$msg: is Program typed node");
        return;
    }
    is($node->operation(), 'Constructor', "$msg: is Constructor");
    is($node->class(), $expected_class, "$msg: class is $expected_class");
}

# Get flattened statement list from Program (handles both typed and Constructor nodes)
my sub program_stmts($ir) {
    if ($ir isa Chalk::IR::Program) {
        return [ $ir->use_decls()->@*, $ir->classes()->@*, $ir->top_level_subs()->@*, $ir->other_stmts()->@* ];
    }
    return $ir->inputs()->[0];
}

my sub is_return_node($node, $msg) {
    ok(defined $node, "$msg: defined");
    return unless defined $node;
    ok($node isa Chalk::IR::Node::Return, "$msg: is Return CFG node");
}

# === Helpers for ClassInfo/ClassDecl dual-path ===

# Validate a class node (ClassInfo or Constructor:ClassDecl)
my sub is_class_node($node, $msg) {
    ok(defined $node, "$msg: defined");
    return unless defined $node;
    ok($node isa Chalk::IR::ClassInfo
        || ($node isa Chalk::IR::Node::Constructor
            && $node->class() eq 'ClassDecl'),
        "$msg: is ClassInfo or ClassDecl");
}

# Get class name from ClassInfo or Constructor:ClassDecl
my sub class_name($cls) {
    return $cls isa Chalk::IR::ClassInfo
        ? $cls->name()
        : $cls->inputs()->[0]->value();
}

# Get class parent name from ClassInfo or Constructor:ClassDecl
my sub class_parent($cls) {
    return $cls isa Chalk::IR::ClassInfo
        ? $cls->parent()
        : (defined $cls->inputs()->[1] ? $cls->inputs()->[1]->value() : undef);
}

# Get class body from ClassInfo or Constructor:ClassDecl
my sub class_body($cls) {
    return $cls isa Chalk::IR::ClassInfo ? $cls->body() : $cls->inputs()->[2];
}

# Get method name from MethodInfo or Constructor:MethodDecl
my sub method_name($meth) {
    return $meth isa Chalk::IR::MethodInfo
        ? $meth->name()
        : $meth->inputs()->[0]->value();
}

# Get method params from MethodInfo or Constructor:MethodDecl
my sub method_params($meth) {
    return $meth isa Chalk::IR::MethodInfo
        ? $meth->params()
        : $meth->inputs()->[1];
}

# Get method body from MethodInfo or Constructor:MethodDecl
my sub method_body($meth) {
    return $meth isa Chalk::IR::MethodInfo ? $meth->body() : $meth->inputs()->[2];
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
        my $stmts = program_stmts($ir);
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

        # Last: class declaration (ClassInfo or ClassDecl)
        my $cls = $stmts->[-1];
        is_class_node($cls, 'Start.pm class declaration');
        is(class_name($cls), 'Chalk::Bootstrap::IR::Node::Start', 'Start.pm class name');
        is(class_parent($cls), 'Chalk::Bootstrap::IR::Node', 'Start.pm parent class');

        # Class body has 1 method
        my $body = class_body($cls);
        is(ref $body, 'ARRAY', 'Start.pm: class body is arrayref');
        my @methods = grep { $_ isa Chalk::IR::MethodInfo
            || ($_ isa Chalk::IR::Node::Constructor && $_->class() eq 'MethodDecl')
        } $body->@*;
        ok(scalar @methods >= 1, 'Start.pm: class body has at least 1 method');

        my ($meth) = @methods;
        is(method_name($meth), 'operation', 'Start.pm method name');

        # Method body has Return CFG node
        my $meth_body = method_body($meth);
        is(ref $meth_body, 'ARRAY', 'Start.pm: method body is arrayref');
        is(scalar $meth_body->@*, 1, 'Start.pm: method body has 1 statement');

        my $ret = $meth_body->[0];
        is_return_node($ret, 'Start.pm return');
        is_constant($ret->inputs()->[1], 'Start', 'Start.pm return value');
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
        my $stmts = program_stmts($ir);
        my $cls = $stmts->[-1];
        is_class_node($cls, 'Return.pm class declaration');
        is(class_name($cls), 'Chalk::Bootstrap::IR::Node::Return', 'Return.pm class name');
        is(class_parent($cls), 'Chalk::Bootstrap::IR::Node', 'Return.pm parent class');

        my $body = class_body($cls);
        my @methods = grep { $_ isa Chalk::IR::MethodInfo
            || ($_ isa Chalk::IR::Node::Constructor && $_->class() eq 'MethodDecl')
        } $body->@*;
        ok(scalar @methods >= 1, 'Return.pm: class body has at least 1 method');
        my ($meth) = @methods;
        is(method_name($meth), 'operation', 'Return.pm method name');

        my $meth_body = method_body($meth);
        my $ret = $meth_body->[0];
        is_return_node($ret, 'Return.pm return');
        is_constant($ret->inputs()->[1], 'Return', 'Return.pm return value');
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
        my $stmts = program_stmts($ir);
        my $cls = $stmts->[-1];
        is_class_node($cls, 'Target.pm class declaration');
        is(class_name($cls), 'Chalk::Bootstrap::Target', 'Target.pm class name');
        is(class_parent($cls), undef, 'Target.pm: no parent class');

        my $body = class_body($cls);
        my @methods = grep { $_ isa Chalk::IR::MethodInfo
            || ($_ isa Chalk::IR::Node::Constructor && $_->class() eq 'MethodDecl')
        } $body->@*;
        ok(scalar @methods >= 2, 'Target.pm: class body has at least 2 methods');

        # Find generate($ir) method
        my ($m1) = grep { method_name($_) eq 'generate' } @methods;
        ok(defined $m1, 'Target.pm: has generate method');
        if (defined $m1) {
            my $m1_params = method_params($m1);
            ok(scalar $m1_params->@* >= 1, 'Target.pm generate has at least 1 param');

            # Body has Unwind (die)
            my $m1_body = method_body($m1);
            is(scalar $m1_body->@*, 1, 'Target.pm generate body has 1 statement');
            isa_ok($m1_body->[0], 'Chalk::IR::Node::Unwind', 'Target.pm generate dies (Unwind CFG node)');
        }

        # Find generate_distribution($ir) method
        my ($m2) = grep { method_name($_) eq 'generate_distribution' } @methods;
        ok(defined $m2, 'Target.pm: has generate_distribution method');
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
        my $stmts = program_stmts($ir);
        my $cls = $stmts->[-1];
        is_class_node($cls, 'Pass.pm class declaration');
        is(class_name($cls), 'Chalk::Bootstrap::Optimizer::Pass', 'Pass.pm class name');
        is(class_parent($cls), undef, 'Pass.pm: no parent class');

        my $body = class_body($cls);
        my @methods = grep { $_ isa Chalk::IR::MethodInfo
            || ($_ isa Chalk::IR::Node::Constructor && $_->class() eq 'MethodDecl')
        } $body->@*;
        ok(scalar @methods >= 2, 'Pass.pm: class body has at least 2 methods');

        # Method: name() - no params
        my ($m1) = grep { method_name($_) eq 'name' } @methods;
        ok(defined $m1, 'Pass.pm: has name method');
        if (defined $m1) {
            is(scalar method_params($m1)->@*, 0, 'Pass.pm name has 0 params');
        }

        # Method: run($ir) - 1 param
        my ($m2) = grep { method_name($_) eq 'run' } @methods;
        ok(defined $m2, 'Pass.pm: has run method');
        if (defined $m2) {
            is(scalar method_params($m2)->@*, 1, 'Pass.pm run has 1 param');
        }
    }
}

done_testing();
