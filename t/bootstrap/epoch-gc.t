# ABOUTME: Tests for epoch-based chart GC via on_epoch_commit callback.
# ABOUTME: Verifies statement-boundary sweeping frees chart memory.
use 5.42.0;
use utf8;
use lib 'lib';
use lib 't/bootstrap/lib';

use Test::More;

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::FilterComposite;
use Chalk::Bootstrap::Semiring::SemanticAction;

# Set up grammar once for all tests that need a real parse
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
eval "$generated; 1" or die "Grammar eval failed: $@";
no strict 'refs';
my $grammar = "Chalk::Grammar::BNF::Generated"->can('grammar')->();

# --- Component A: on_complete accepts callback parameter ---

# Test 1: on_complete with callback doesn't crash (Boolean)
{
    my $bool = Chalk::Bootstrap::Semiring::Boolean->new();
    my $item = { rule => bless({}, 'FakeRule'), value => true, origin => 0 };
    # Provide a fake rule with name() method
    no warnings 'once';
    local *FakeRule::name = sub { 'TestRule' };
    local *FakeRule::expressions = sub { [[]] };
    my $callback_fired = false;
    my $cb = sub ($origin, $end) { $callback_fired = true };
    my $result = eval { $bool->on_complete($item, 0, 10, $cb) };
    is($@, '', 'Boolean on_complete accepts 4th callback parameter without error');
}

# Test 2: on_complete without callback still works (backward compat)
{
    my $bool = Chalk::Bootstrap::Semiring::Boolean->new();
    my $item = { rule => bless({}, 'FakeRule'), value => true, origin => 0 };
    my $result = eval { $bool->on_complete($item, 0, 10) };
    is($@, '', 'Boolean on_complete still works with 3 params');
}

# Test 3: FilterComposite passes callback through to components
{
    my $callback_args;
    my $cb = sub ($origin, $end) {
        $callback_args = [$origin, $end];
    };

    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $parser = build_perl_ir_parser($grammar, start => 'Program');
    my $semiring = $parser->semiring();
    $semiring->reset_cache();

    # Parse a multi-statement input
    my $result = $parser->parse_value("my \$x = 1;\nmy \$y = 2;\n");
    ok(defined $result, 'multi-statement parse succeeds');
    # Callback should NOT have fired yet — we haven't wired it
    ok(!defined $callback_args, 'callback not fired without wiring (Component B needed)');
}

# --- Component B: SemanticAction fires callback on Statement completion ---

# Test 5: SemanticAction calls on_epoch_commit for StatementItem rule
{
    use Chalk::Bootstrap::ConciseTree::Actions;
    my $actions = Chalk::Bootstrap::ConciseTree::Actions->new();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new(actions => $actions);

    my @epochs;
    my $cb = sub ($origin, $end) {
        push @epochs, [$origin, $end];
    };

    # Simulate a completed StatementItem — the rule that wraps individual
    # statements in the grammar
    my $fake_rule = bless({}, 'FakeStatementRule');
    no warnings 'redefine';
    local *FakeStatementRule::name = sub { 'StatementItem' };
    local *FakeStatementRule::expressions = sub { [[]] };

    # Create a Context as the item value (SemanticAction expects this)
    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => { class => 'VarDecl', inputs => [] },
        children => [],
        position => 0,
    );

    my $item = { rule => $fake_rule, value => $ctx, origin => 5 };
    $sa->on_complete($item, 0, 20, $cb);

    ok(scalar @epochs > 0, 'on_epoch_commit fires for StatementItem completion');
    if (@epochs) {
        is($epochs[0][0], 5, 'epoch origin matches item origin');
        is($epochs[0][1], 20, 'epoch end matches completion position');
    }
}

# Test 6: SemanticAction does NOT fire callback for non-statement rules
{
    use Chalk::Bootstrap::ConciseTree::Actions;
    my $actions = Chalk::Bootstrap::ConciseTree::Actions->new();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new(actions => $actions);

    my @epochs;
    my $cb = sub ($origin, $end) {
        push @epochs, [$origin, $end];
    };

    my $fake_rule = bless({}, 'FakeExprRule');
    no warnings 'redefine';
    local *FakeExprRule::name = sub { 'Expression' };
    local *FakeExprRule::expressions = sub { [[]] };

    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => { class => 'NumericLiteral', value => '42' },
        children => [],
        position => 0,
    );

    my $item = { rule => $fake_rule, value => $ctx, origin => 0 };
    $sa->on_complete($item, 0, 5, $cb);

    is(scalar @epochs, 0, 'on_epoch_commit does NOT fire for Expression completion');
}

# --- Component C: Earley sweep queue wires callback and frees positions ---

# Test 9: gc_freed > 0 after multi-statement parse
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $parser = build_perl_ir_parser($grammar, start => 'Program');
    my $semiring = $parser->semiring();
    $semiring->reset_cache();

    # Parse 5 statements — should trigger epoch sweeps
    my $source = "my \$a = 1;\nmy \$b = 2;\nmy \$c = 3;\nmy \$d = 4;\nmy \$e = 5;\n";
    my $result = $parser->parse_value($source);
    ok(defined $result, '5-statement parse succeeds');

    my $gc = $parser->gc_stats();
    my $freed = $gc->{positions_freed} // 0;
    cmp_ok($freed, '>', 0, "gc_freed > 0 after multi-statement parse (got $freed)");
}

# --- Component E: Full semiring parse has GC ---

# Test 11: Full semiring parse frees positions
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $parser = build_perl_ir_parser($grammar, start => 'Program');
    my $semiring = $parser->semiring();
    $semiring->reset_cache();

    my $result = $parser->parse_value("my \$a = 1;\nmy \$b = 2;\nmy \$c = 3;\n");
    ok(defined $result, 'full semiring 3-statement parse succeeds');
    my $gc = $parser->gc_stats();
    my $freed = $gc->{positions_freed} // 0;
    cmp_ok($freed, '>', 0, "full semiring gc_freed > 0 (got $freed)");
}

# Test 12: Parse result is correct despite GC
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $parser = build_perl_ir_parser($grammar, start => 'Program');
    my $semiring = $parser->semiring();
    $semiring->reset_cache();

    my $result = $parser->parse_value("my \$x = 42;\n");
    ok(defined $result, 'single statement parse with GC succeeds');
    ok(!$semiring->is_zero($result), 'result is not zero');
    # Check the SemanticAction produced a valid IR
    my $sa_val = $result->[4];
    ok(defined $sa_val, 'SemanticAction component has value');
    if (defined $sa_val) {
        my $ir = $sa_val->extract();
        ok(defined $ir, 'IR extraction succeeds after GC');
    }
}

# --- Safe-Set GC (Aycock Ch6) ---

# Test 17: Boolean-only parse has gc_freed > 0 with safe-set GC
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $parser = build_perl_ir_parser($grammar, start => 'Program');
    my $bool = Chalk::Bootstrap::Semiring::Boolean->new();
    my $bp = Chalk::Bootstrap::Earley->new(
        grammar => $parser->grammar(),
        semiring => $bool,
    );

    my $source = "my \$a = 1;\nmy \$b = 2;\nmy \$c = 3;\n";
    my $w = ''; local $SIG{__WARN__} = sub { $w .= $_[0] };
    my $result = $bp->parse_value($source);
    ok(defined $result, 'Boolean 3-statement parse succeeds');
    ok(!$bool->is_zero($result), 'result is not zero');

    my $gc = $bp->gc_stats();
    my $freed = $gc->{positions_freed} // 0;
    TODO: {
        local $TODO = 'safe-set window freeing breaks cross-boundary references';
        cmp_ok($freed, '>', 0, "Boolean parse gc_freed > 0 with safe-set GC (got $freed)");
    }
}

done_testing();
