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

# --- Test 5: Full pipeline round-trip: generate_with_cfg produces valid Perl ---
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

    # Parse if/else and verify generate_with_cfg produces valid Perl with if/else
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring2->reset_cache();

        my $result = $parser2->parse_value('if (1) { 42 } else { 99 }');
        ok(defined $result, 'if/else parses for generate test');

        my $sem_ctx = $result->[4];
        my $ir_node = $sem_ctx->extract();
        ok(defined $ir_node, 'IR node extracted');

        my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
        my $code = $perl_target->generate_with_cfg($ir_node, $sa2, $sem_ctx);
        ok(defined $code, 'generate_with_cfg produces code');
        like($code, qr/if\s*\(/, 'generated code contains if statement');
        like($code, qr/else/, 'generated code contains else');
        like($code, qr/'42'/, 'generated code contains then body');
        like($code, qr/'99'/, 'generated code contains else body');
    }

    # Parse if-without-else and verify no spurious else block
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring2->reset_cache();

        my $result = $parser2->parse_value('if (1) { 42 }');
        ok(defined $result, 'if-no-else parses for generate test');

        my $sem_ctx = $result->[4];
        my $ir_node = $sem_ctx->extract();
        ok(defined $ir_node, 'IR node extracted for if-no-else');

        my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
        my $code = $perl_target->generate_with_cfg($ir_node, $sa2, $sem_ctx);
        ok(defined $code, 'generate_with_cfg produces code for if-no-else');
        like($code, qr/if\s*\(/, 'generated code contains if');
        like($code, qr/'42'/, 'generated code contains then body');
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

# --- Test 6: IR statement list contains CFG nodes, not legacy Constructors ---
SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::CfgNodeTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::CfgNodeTest::grammar();
    my $parser3 = build_perl_ir_parser($gen_grammar, start => 'Program');
    skip 'IR parser not built', 1 unless defined $parser3;

    my $semiring3 = $parser3->semiring();
    my $sa3 = $semiring3->semirings()->[4];

    # Parse if/else and verify the IR node doesn't contain IfStmt Constructor
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring3->reset_cache();

        my $result = $parser3->parse_value('if (1) { 42 } else { 99 }');
        ok(defined $result, 'if/else parses for CFG node test');

        my $sem_ctx = $result->[4];
        my $ir_node = $sem_ctx->extract();
        ok(defined $ir_node, 'IR node extracted for if/else');

        # The Program's statement list should contain a CFG If node, not IfStmt Constructor
        my $stmts = $ir_node->inputs()->[0];
        ok(ref($stmts) eq 'ARRAY', 'Program inputs[0] is array');

        my @if_stmts = grep {
            $_ isa Chalk::Bootstrap::IR::Node::Constructor
            && $_->class() eq 'IfStmt'
        } $stmts->@*;
        is(scalar @if_stmts, 0, 'no IfStmt Constructor in statement list');

        my @cfg_nodes = grep {
            $_ isa Chalk::Bootstrap::IR::Node
            && $_->operation() eq 'If'
        } $stmts->@*;
        ok(scalar @cfg_nodes > 0, 'If CFG node present in statement list');
    }

    # Parse foreach and verify no ForeachLoop Constructor
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring3->reset_cache();

        my $result = $parser3->parse_value('for my $x (1, 2, 3) { $x }');
        ok(defined $result, 'foreach parses for CFG node test');

        my $sem_ctx = $result->[4];
        my $ir_node = $sem_ctx->extract();
        ok(defined $ir_node, 'IR node extracted for foreach');

        my $stmts = $ir_node->inputs()->[0];
        ok(ref($stmts) eq 'ARRAY', 'Program inputs[0] is array for foreach');

        my @foreach_stmts = grep {
            $_ isa Chalk::Bootstrap::IR::Node::Constructor
            && $_->class() eq 'ForeachLoop'
        } $stmts->@*;
        is(scalar @foreach_stmts, 0, 'no ForeachLoop Constructor in statement list');

        my @cfg_loops = grep {
            $_ isa Chalk::Bootstrap::IR::Node
            && $_->operation() eq 'Loop'
        } $stmts->@*;
        ok(scalar @cfg_loops > 0, 'Loop CFG node present in statement list');
    }
}

# --- Test 7: PostfixModifier returns CFG nodes, not PostfixLoop Constructors ---
# Uses real file parsing to verify PostfixModifier returns CFG nodes for
# postfix if/unless. PostfixLoop body is undef (dead constructor).
SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::PostfixCfgTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::PostfixCfgTest::grammar();

    # Parse ConciseOp.pm which uses postfix if in method bodies
    use TestXSHelpers qw(parse_file_ir);
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my ($file_ir, $file_sa, $file_ctx) = parse_file_ir($gen_grammar,
        'lib/Chalk/Bootstrap/ConciseOp.pm');
    ok(defined $file_ir, 'ConciseOp.pm parses for postfix CFG test');

    SKIP: {
        skip 'ConciseOp.pm: no IR', 2 unless defined $file_ir;

        # Walk all IR nodes looking for PostfixLoop Constructors
        my @stack = ($file_ir);
        my $found_postfix_loop = false;
        while (@stack) {
            my $node = pop @stack;
            if ($node isa Chalk::Bootstrap::IR::Node::Constructor) {
                $found_postfix_loop = true if $node->class() eq 'PostfixLoop';
                for my $input ($node->inputs()->@*) {
                    if (ref($input) eq 'ARRAY') {
                        push @stack, grep { defined && ref } $input->@*;
                    } elsif (defined $input && ref($input)) {
                        push @stack, $input;
                    }
                }
            }
        }
        ok(!$found_postfix_loop, 'no PostfixLoop Constructor in ConciseOp IR');

        # Verify cfg_state has if_node entries (from postfix if in method bodies)
        my @ctx_stack = ($file_ctx);
        my $cfg_if_count = 0;
        while (@ctx_stack) {
            my $ctx = pop @ctx_stack;
            my $state = $file_sa->cfg_state($ctx);
            if (defined $state && defined $state->{if_node}) {
                $cfg_if_count++;
            }
            push @ctx_stack, reverse $ctx->children()->@*;
        }
        ok($cfg_if_count > 0, "ConciseOp has cfg_state If entries ($cfg_if_count)");
    }
}

# --- Test 8: unless negates condition in IfStatement CFG nodes ---
SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::UnlessTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::UnlessTest::grammar();
    my $parser_u = build_perl_ir_parser($gen_grammar, start => 'Program');
    skip 'IR parser not built', 1 unless defined $parser_u;

    my $semiring_u = $parser_u->semiring();
    my $sa_u = $semiring_u->semirings()->[4];

    # unless generates negated condition in If CFG node
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring_u->reset_cache();

        my $result = $parser_u->parse_value('unless (1) { 42 }');
        ok(defined $result, 'unless parses');

        my $sem_ctx = $result->[4];
        my $state = $sa_u->cfg_state($sem_ctx);
        ok(defined $state, 'cfg_state exists after unless');
        ok(defined $state->{if_node}, 'if_node present for unless');

        # The If node's condition should be a negated expression (UnaryExpr '!')
        my $if_cond = $state->{if_node}->inputs()->[1];
        ok(defined $if_cond, 'If condition exists');
        ok($if_cond isa Chalk::Bootstrap::IR::Node::Constructor
            && $if_cond->class() eq 'UnaryExpr',
            'unless condition is UnaryExpr (negation)');
    }

    # Codegen: unless produces if (!...) in output
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring_u->reset_cache();

        my $result = $parser_u->parse_value('unless (1) { 42 }');
        ok(defined $result, 'unless parses for codegen test');

        my $sem_ctx = $result->[4];
        my $ir_node = $sem_ctx->extract();
        my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
        my $code = $perl_target->generate_with_cfg($ir_node, $sa_u, $sem_ctx);
        ok(defined $code, 'unless generates code');
        like($code, qr/if\s*\(\s*!/, 'unless generates if (! ...) in output');
    }
}

# --- Test 9: if-without-else does not emit empty else block ---
SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::NoElseTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::NoElseTest::grammar();
    my $parser_ne = build_perl_ir_parser($gen_grammar, start => 'Program');
    skip 'IR parser not built', 1 unless defined $parser_ne;

    my $semiring_ne = $parser_ne->semiring();
    my $sa_ne = $semiring_ne->semirings()->[4];

    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring_ne->reset_cache();

        my $result = $parser_ne->parse_value('if (1) { 42 }');
        ok(defined $result, 'if-no-else parses for empty-else test');

        my $sem_ctx = $result->[4];
        my $ir_node = $sem_ctx->extract();
        my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
        my $code = $perl_target->generate_with_cfg($ir_node, $sa_ne, $sem_ctx);
        ok(defined $code, 'if-no-else generates code');
        unlike($code, qr/\}\s*else\s*\{/, 'no empty else block in output');
    }
}

# --- Test 10: elsif chain emits elsif, not nested if/else ---
SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ElsifTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::ElsifTest::grammar();
    my $parser_el = build_perl_ir_parser($gen_grammar, start => 'Program');
    skip 'IR parser not built', 1 unless defined $parser_el;

    my $semiring_el = $parser_el->semiring();
    my $sa_el = $semiring_el->semirings()->[4];

    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring_el->reset_cache();

        my $result = $parser_el->parse_value('if (1) { 42 } elsif (2) { 99 } else { 0 }');
        ok(defined $result, 'if/elsif/else parses for elsif test');

        my $sem_ctx = $result->[4];
        my $ir_node = $sem_ctx->extract();
        my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
        my $code = $perl_target->generate_with_cfg($ir_node, $sa_el, $sem_ctx);
        ok(defined $code, 'if/elsif/else generates code');
        like($code, qr/\}\s*elsif\s*\(/, 'output contains elsif (not nested if)');
    }
}

# --- Test 11: foreach emits for syntax, not while ---
SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ForTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::ForTest::grammar();
    my $parser_f = build_perl_ir_parser($gen_grammar, start => 'Program');
    skip 'IR parser not built', 1 unless defined $parser_f;

    my $semiring_f = $parser_f->semiring();
    my $sa_f = $semiring_f->semirings()->[4];

    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring_f->reset_cache();

        my $result = $parser_f->parse_value('for my $x (1, 2, 3) { $x }');
        ok(defined $result, 'foreach parses for syntax test');

        my $sem_ctx = $result->[4];
        my $ir_node = $sem_ctx->extract();
        my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
        my $code = $perl_target->generate_with_cfg($ir_node, $sa_f, $sem_ctx);
        ok(defined $code, 'foreach generates code');
        like($code, qr/for\s+my\s+\$/, 'output contains for my $... (not while)');
    }
}

# --- Test 12: Deep elsif chain (3+ branches) ---
SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::DeepElsifTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::DeepElsifTest::grammar();
    my $parser_de = build_perl_ir_parser($gen_grammar, start => 'Program');
    skip 'IR parser not built', 1 unless defined $parser_de;

    my $semiring_de = $parser_de->semiring();
    my $sa_de = $semiring_de->semirings()->[4];

    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring_de->reset_cache();

        my $result = $parser_de->parse_value('if (1) { 10 } elsif (2) { 20 } elsif (3) { 30 } else { 40 }');
        ok(defined $result, 'deep elsif chain parses');

        SKIP: {
            skip 'deep elsif chain did not parse', 4 unless defined $result;
            my $sem_ctx = $result->[4];
            my $ir_node = $sem_ctx->extract();
            my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
            my $code = $perl_target->generate_with_cfg($ir_node, $sa_de, $sem_ctx);
            ok(defined $code, 'deep elsif chain generates code');
            # Count elsif occurrences — should have 2 elsif keywords
            my @elsifs = ($code =~ /elsif/g);
            is(scalar @elsifs, 2, 'deep elsif chain has exactly 2 elsif keywords');
            like($code, qr/20/, 'deep elsif chain contains second branch body');
            like($code, qr/30/, 'deep elsif chain contains third branch body');
        }
    }
}

# --- Test 13: Postfix if wires body expression into then_stmts ---
SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::PostfixBodyTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::PostfixBodyTest::grammar();
    my $parser_f = build_perl_ir_parser($gen_grammar, start => 'Program');
    skip 'IR parser not built', 1 unless defined $parser_f;

    my $semiring_f = $parser_f->semiring();
    my $sa_f = $semiring_f->semirings()->[4];

    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring_f->reset_cache();

        my $result = $parser_f->parse_value('42 if 1;');
        ok(defined $result, 'postfix if parses for body wiring test');

        SKIP: {
            skip 'postfix if did not parse', 2 unless defined $result;
            my $sem_ctx = $result->[4];
            my $ir_node = $sem_ctx->extract();
            my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
            my $code = $perl_target->generate_with_cfg($ir_node, $sa_f, $sem_ctx);
            ok(defined $code, 'postfix if generates code');
            like($code, qr/if.*\{.*42/s, 'postfix if body (42) appears inside if block');
        }
    }
}

# --- Test 14: unless with else generates correct code ---
SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::UnlessElseTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::UnlessElseTest::grammar();
    my $parser_ue = build_perl_ir_parser($gen_grammar, start => 'Program');
    skip 'IR parser not built', 1 unless defined $parser_ue;

    my $semiring_ue = $parser_ue->semiring();
    my $sa_ue = $semiring_ue->semirings()->[4];

    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring_ue->reset_cache();

        my $result = $parser_ue->parse_value('unless (0) { 42 } else { 99 }');
        ok(defined $result, 'unless+else parses');

        SKIP: {
            skip 'unless+else did not parse', 3 unless defined $result;
            my $sem_ctx = $result->[4];
            my $ir_node = $sem_ctx->extract();
            my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
            my $code = $perl_target->generate_with_cfg($ir_node, $sa_ue, $sem_ctx);
            ok(defined $code, 'unless+else generates code');
            like($code, qr/if\s*\(\s*!/, 'unless+else emits negated condition');
            like($code, qr/else/, 'unless+else has else block');
        }
    }
}

# --- Test 15: foreach with array variable ---
SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ForArrayTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::ForArrayTest::grammar();
    my $parser_fa = build_perl_ir_parser($gen_grammar, start => 'Program');
    skip 'IR parser not built', 1 unless defined $parser_fa;

    my $semiring_fa = $parser_fa->semiring();
    my $sa_fa = $semiring_fa->semirings()->[4];

    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring_fa->reset_cache();

        my $result = $parser_fa->parse_value('for my $x (@arr) { $x }');
        ok(defined $result, 'foreach with @array parses');

        SKIP: {
            skip 'foreach with @array did not parse', 2 unless defined $result;
            my $sem_ctx = $result->[4];
            my $ir_node = $sem_ctx->extract();
            my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
            my $code = $perl_target->generate_with_cfg($ir_node, $sa_fa, $sem_ctx);
            ok(defined $code, 'foreach with @array generates code');
            like($code, qr/for\s+my\s+\$x/, 'foreach with @array uses for my syntax');
        }
    }
}

done_testing();
