# ABOUTME: Tests that cfg_state carries statement lists per control region.
# ABOUTME: Verifies the eager pinning approach for Sea of Nodes code generation.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Scope;

# --- Test 1: cfg_state accepts and returns statements field ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $ctx = $sa->one();
    my $start = $factory->make('Start');
    my $stmt1 = $factory->make('Constant', const_type => 'string', value => 'hello');

    $sa->set_cfg_state($ctx, {
        control    => $start,
        scope      => Chalk::Bootstrap::Scope->new(),
        statements => [$stmt1],
    });

    my $state = $sa->cfg_state($ctx);
    ok(defined $state, 'cfg_state returns state with statements');
    is(ref($state->{statements}), 'ARRAY', 'statements is an arrayref');
    is(scalar($state->{statements}->@*), 1, 'statements has one entry');
    is($state->{statements}->[0], $stmt1, 'statement is the expected node');
}

# --- Test 2: cfg_state accepts if_node, true_proj, false_proj references ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $ctx = $sa->one();
    my $start = $factory->make('Start');
    my $cond  = $factory->make('Constant', const_type => 'integer', value => 1);
    my $if_node    = $factory->make('If', control => $start, condition => $cond);
    my $true_proj  = $factory->make('Proj', source => $if_node, index => 0);
    my $false_proj = $factory->make('Proj', source => $if_node, index => 1);
    my $region     = $factory->make('Region', controls => [$true_proj, $false_proj]);

    my $then_stmt = $factory->make('Constant', const_type => 'integer', value => 42);
    my $else_stmt = $factory->make('Constant', const_type => 'integer', value => 99);

    $sa->set_cfg_state($ctx, {
        control    => $region,
        scope      => Chalk::Bootstrap::Scope->new(),
        then_stmts => [$then_stmt],
        else_stmts => [$else_stmt],
        if_node    => $if_node,
        true_proj  => $true_proj,
        false_proj => $false_proj,
    });

    my $state = $sa->cfg_state($ctx);
    ok(defined $state, 'cfg_state with if structure exists');
    is($state->{control}->operation(), 'Region', 'control is Region');
    is($state->{if_node}->operation(), 'If', 'if_node is If');
    is($state->{true_proj}->operation(), 'Proj', 'true_proj is Proj');
    is($state->{false_proj}->operation(), 'Proj', 'false_proj is Proj');
    is(ref($state->{then_stmts}), 'ARRAY', 'then_stmts is array');
    is(ref($state->{else_stmts}), 'ARRAY', 'else_stmts is array');
    is($state->{then_stmts}->[0], $then_stmt, 'then_stmts contains expected node');
    is($state->{else_stmts}->[0], $else_stmt, 'else_stmts contains expected node');
}

# --- Test 3: cfg_state accepts loop structure references ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $ctx = $sa->one();
    my $start = $factory->make('Start');
    my $loop_cond = $factory->make('Constant', const_type => 'string', value => '__loop_bound__');
    my $loop      = $factory->make('Loop', entry_ctrl => $start, backedge_ctrl => undef);
    my $loop_if   = $factory->make('If', control => $loop, condition => $loop_cond);
    my $body_proj = $factory->make('Proj', source => $loop_if, index => 0);
    my $exit_proj = $factory->make('Proj', source => $loop_if, index => 1);
    my $region    = $factory->make('Region', controls => [$exit_proj]);

    my $body_stmt = $factory->make('Constant', const_type => 'string', value => 'body');
    my $iterator  = $factory->make('Constant', const_type => 'string', value => '$x');
    my $list_node = $factory->make('Constant', const_type => 'string', value => 'list');

    $sa->set_cfg_state($ctx, {
        control    => $region,
        scope      => Chalk::Bootstrap::Scope->new(),
        body_stmts => [$body_stmt],
        loop       => $loop,
        loop_if    => $loop_if,
        body_proj  => $body_proj,
        exit_proj  => $exit_proj,
        iterator   => $iterator,
        list       => $list_node,
    });

    my $state = $sa->cfg_state($ctx);
    ok(defined $state, 'cfg_state with loop structure exists');
    is($state->{control}->operation(), 'Region', 'control is Region');
    is($state->{loop}->operation(), 'Loop', 'loop is Loop');
    is($state->{loop_if}->operation(), 'If', 'loop_if is If');
    is($state->{body_proj}->operation(), 'Proj', 'body_proj is Proj');
    is($state->{exit_proj}->operation(), 'Proj', 'exit_proj is Proj');
    is(ref($state->{body_stmts}), 'ARRAY', 'body_stmts is array');
    is($state->{body_stmts}->[0], $body_stmt, 'body_stmts contains expected node');
    is($state->{iterator}, $iterator, 'iterator stored');
    is($state->{list}, $list_node, 'list stored');
}

# --- Test 4: IfStatement populates cfg_state with body statements (integration) ---
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::Target::Perl;
use Chalk::Bootstrap::Perl::Target::Perl;

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::CfgStmtTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::CfgStmtTest::grammar();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    skip 'IR parser not built', 1 unless defined $parser;

    my $semiring = $parser->semiring();
    my $sa = $semiring->semirings()->[4];
    ok($sa isa Chalk::Bootstrap::Semiring::SemanticAction, 'got SemanticAction from parser');

    # --- IfStatement stores then_stmts and else_stmts ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $result = $parser->parse_value('if (1) { 42 } else { 99 }');
        ok(defined $result, 'if/else parses');

        my $sem_ctx = $result->[4];
        my $state = $sa->cfg_state($sem_ctx);
        ok(defined $state, 'cfg_state exists after if/else');

        my $control = $state->{control};
        is($control->operation(), 'Region', 'control is Region after if/else');

        # Verify IfStatement stored body statements
        ok(defined $state->{then_stmts}, 'then_stmts present in cfg_state');
        ok(defined $state->{else_stmts}, 'else_stmts present in cfg_state');
        is(ref($state->{then_stmts}), 'ARRAY', 'then_stmts is array');
        is(ref($state->{else_stmts}), 'ARRAY', 'else_stmts is array');

        # Verify CFG node references stored
        ok(defined $state->{if_node}, 'if_node present in cfg_state');
        is($state->{if_node}->operation(), 'If', 'if_node is If');
        ok(defined $state->{true_proj}, 'true_proj present');
        ok(defined $state->{false_proj}, 'false_proj present');
        is($state->{true_proj}->operation(), 'Proj', 'true_proj is Proj');
        is($state->{false_proj}->operation(), 'Proj', 'false_proj is Proj');
    }

    # --- IfStatement without else stores then_stmts only ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $result = $parser->parse_value('if (1) { 42 }');
        ok(defined $result, 'if without else parses');

        my $sem_ctx = $result->[4];
        my $state = $sa->cfg_state($sem_ctx);
        ok(defined $state, 'cfg_state exists after if');

        ok(defined $state->{then_stmts}, 'then_stmts present for if-without-else');
        is(ref($state->{then_stmts}), 'ARRAY', 'then_stmts is array');
        ok(defined $state->{if_node}, 'if_node present for if-without-else');
    }

    # --- ElsifChain stores body statements and has its own if_node ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $result = $parser->parse_value('if (1) { 42 } elsif (2) { 99 } else { 0 }');
        ok(defined $result, 'if/elsif/else parses');

        my $sem_ctx = $result->[4];
        my $state = $sa->cfg_state($sem_ctx);
        ok(defined $state, 'cfg_state exists after if/elsif/else');

        # The outer if should have then_stmts and if_node
        ok(defined $state->{then_stmts}, 'outer if has then_stmts');
        ok(defined $state->{if_node}, 'outer if has if_node');
        is($state->{if_node}->operation(), 'If', 'outer if_node is If');
    }

    # --- ForeachStatement stores body_stmts and loop structure ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $result = $parser->parse_value('for my $x (1, 2, 3) { $x }');
        ok(defined $result, 'foreach parses');

        my $sem_ctx = $result->[4];
        my $state = $sa->cfg_state($sem_ctx);
        ok(defined $state, 'cfg_state exists after foreach');

        my $control = $state->{control};
        is($control->operation(), 'Region', 'control is Region after foreach');

        # Verify loop structure stored
        ok(defined $state->{body_stmts}, 'body_stmts present in cfg_state');
        is(ref($state->{body_stmts}), 'ARRAY', 'body_stmts is array');
        ok(defined $state->{loop}, 'loop present in cfg_state');
        is($state->{loop}->operation(), 'Loop', 'loop is Loop');
        ok(defined $state->{loop_if}, 'loop_if present');
        is($state->{loop_if}->operation(), 'If', 'loop_if is If');
        ok(defined $state->{body_proj}, 'body_proj present');
        ok(defined $state->{exit_proj}, 'exit_proj present');
        ok(defined $state->{iterator}, 'iterator present');
        ok(exists $state->{list}, 'list key exists in cfg_state');
    }
}

# --- Test 5: Full pipeline: generate() uses cfg_state for if/else ---
SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::CfgGenTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::CfgGenTest::grammar();
    my $parser2 = build_perl_ir_parser($gen_grammar, start => 'Program');
    skip 'IR parser not built', 1 unless defined $parser2;

    my $semiring2 = $parser2->semiring();
    my $sa2 = $semiring2->semirings()->[4];

    # Parse if/else and get both IR and SemanticAction context
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring2->reset_cache();

        my $result = $parser2->parse_value('if (1) { 42 } else { 99 }');
        ok(defined $result, 'if/else parses for generate test');

        my $sem_ctx = $result->[4];
        my $ir_node = $sem_ctx->extract();
        ok(defined $ir_node, 'IR node extracted');

        # generate_with_cfg should use cfg_state for control flow
        my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
        my $code = $perl_target->generate_with_cfg($ir_node, $sa2, $sem_ctx);
        ok(defined $code, 'generate_with_cfg produces code');
        like($code, qr/if\s*\(/, 'generated code contains if statement');
        like($code, qr/else/, 'generated code contains else');
    }

    # Parse foreach and verify cfg_state dispatch
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring2->reset_cache();

        my $result = $parser2->parse_value('for my $x (1, 2, 3) { $x }');
        ok(defined $result, 'foreach parses for generate test');

        my $sem_ctx = $result->[4];
        my $ir_node = $sem_ctx->extract();
        ok(defined $ir_node, 'IR node extracted for foreach');

        my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
        my $code = $perl_target->generate_with_cfg($ir_node, $sa2, $sem_ctx);
        ok(defined $code, 'generate_with_cfg produces code for foreach');
        like($code, qr/(?:while|for)/, 'generated code contains loop');
    }
}

done_testing();
