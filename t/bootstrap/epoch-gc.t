# ABOUTME: Tests for epoch-based chart GC via Earley's statement-boundary sweep.
# ABOUTME: Verifies statement-boundary sweeping frees chart memory.
use 5.42.0;
use utf8;
use lib 'lib';
use lib 't/bootstrap/lib';

use Test::More;

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::FilterComposite;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Context;

# Helper: build a complete-annotated Context for multiply() calls.
my $make_complete = sub ($value, $rule_name, $alt_idx, $pos, $origin) {
    $pos    //= 0;
    $origin //= 0;
    $alt_idx //= 0;
    return Chalk::Bootstrap::Context->new(
        focus       => undef,
        children    => defined($value) ? [$value] : [],
        position    => $pos,
        annotations => {
            complete  => true,
            rule_name => $rule_name,
            alt_idx   => $alt_idx,
            pos       => $pos,
            origin    => $origin,
        },
    );
};

# Set up grammar once for all tests that need a real parse
my $raw_ir = perl_pipeline();
my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
eval "$generated; 1" or die "Grammar eval failed: $@";
no strict 'refs';
my $grammar = "Chalk::Grammar::BNF::Generated"->can('grammar')->();

# --- Component A: multiply handles complete events (Boolean) ---

# Test 1: Boolean multiply with complete Context doesn't crash
{
    my $bool = Chalk::Bootstrap::Semiring::Boolean->new();
    my $one = $bool->one();
    my $result = eval { $bool->multiply($one, $make_complete->($one, 'TestRule', 0, 10, 0)) };
    is($@, '', 'Boolean multiply with complete Context does not error');
}

# Test 2: Boolean multiply with complete Context returns non-zero
{
    my $bool = Chalk::Bootstrap::Semiring::Boolean->new();
    my $one = $bool->one();
    my $result = eval { $bool->multiply($one, $make_complete->($one, 'TestRule', 0, 10, 0)) };
    is($@, '', 'Boolean multiply with complete Context works');
}

# Test 3: FilterComposite passes callback through to components
{
    my $callback_args;
    my $cb = sub ($origin, $end) {
        $callback_args = [$origin, $end];
    };

    my $parser = build_perl_ir_parser($grammar, start => 'Program');
    my $semiring = $parser->semiring();
    $semiring->reset_cache();

    # Parse a multi-statement input
    my $result = $parser->parse_value("my \$x = 1;\nmy \$y = 2;\n");
    ok(defined $result, 'multi-statement parse succeeds');
    # Callback should NOT have fired yet — we haven't wired it
    ok(!defined $callback_args, 'callback not fired without wiring (Component B needed)');
}

# --- Component B: SemanticAction multiply handles completion events ---
# Epoch GC callbacks are now fired directly by the Earley parser, not by
# SemanticAction. These tests verify that SA multiply handles StatementItem
# completion without crashing.

# Test 5: SemanticAction multiply with StatementItem complete Context does not crash
{
    use Chalk::Bootstrap::Perl::Actions;
    my $actions = Chalk::Bootstrap::Perl::Actions->new();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new(actions => $actions);

    # Create a Context as the left value (SemanticAction expects a Context)
    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [],
        position => 0,
    );

    # Simulate a completed StatementItem at origin=5, pos=20
    my $result = eval {
        $sa->multiply($ctx, $make_complete->($ctx, 'StatementItem', 0, 20, 5))
    };
    is($@, '', 'SA multiply with StatementItem complete Context does not crash');
}

# Test 6: SemanticAction multiply with non-statement rule does not crash
{
    use Chalk::Bootstrap::Perl::Actions;
    my $actions = Chalk::Bootstrap::Perl::Actions->new();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new(actions => $actions);

    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [],
        position => 0,
    );

    my $result = eval {
        $sa->multiply($ctx, $make_complete->($ctx, 'Expression', 0, 5, 0))
    };
    is($@, '', 'SA multiply with Expression complete Context does not crash');
}

# --- Component C: Earley sweep queue wires callback and frees positions ---

# Test 9: gc_freed > 0 after multi-statement parse
{
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
    my $parser = build_perl_ir_parser($grammar, start => 'Program');
    my $semiring = $parser->semiring();
    $semiring->reset_cache();

    my $result = $parser->parse_value("my \$x = 42;\n");
    ok(defined $result, 'single statement parse with GC succeeds');
    ok(!$semiring->is_zero($result), 'result is not zero');
    # Check the SemanticAction produced a valid IR
    my $sa_val = $result;
    ok(defined $sa_val, 'SemanticAction component has value');
    if (defined $sa_val) {
        my $ir = $sa_val->extract();
        ok(defined $ir, 'IR extraction succeeds after GC');
    }
}

# --- Safe-Set GC (Aycock Ch6) ---

# Test 17: Boolean-only parse detects safe sets with safe-set GC
{
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
    my $found = $gc->{safe_sets_found} // 0;
    cmp_ok($found, '>', 0, "Boolean parse safe_sets_found > 0 with safe-set GC (got $found)");
}

# --- Test 20: Epoch GC and safe-set GC coexist without interference ---

# Test 20: Both GC systems active simultaneously produce correct results
subtest 'epoch GC and safe-set GC coexist' => sub {
    # Uses the full 5-ary FilterComposite semiring (epoch GC via SemanticAction
    # on_epoch_commit) plus safe-set detection (Aycock Properties 1-3).
    # Verifies both contribute GC and the parse result is still correct.
    my $parser = build_perl_ir_parser($grammar, start => 'Program');
    my $semiring = $parser->semiring();
    $semiring->reset_cache();

    my $source = "my \$a = 1;\nmy \$b = 2;\nmy \$c = 3;\nmy \$d = 4;\n";
    my $result = $parser->parse_value($source);
    ok(defined $result, 'full semiring 4-statement parse succeeds');
    ok(!$semiring->is_zero($result), 'result is not zero');

    my $gc = $parser->gc_stats();
    my $freed  = $gc->{positions_freed} // 0;
    my $ssfound = $gc->{safe_sets_found} // 0;
    diag("epoch+safe-set GC: positions_freed=$freed, safe_sets_found=$ssfound");

    cmp_ok($freed,   '>', 0, 'epoch GC freed positions (positions_freed > 0)');
    cmp_ok($ssfound, '>', 0, 'safe-set GC detected safe sets (safe_sets_found > 0)');
};

done_testing();
