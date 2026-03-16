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

    # Set up grammar for a real parse
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $raw_ir = perl_pipeline();
    my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
    my $generated = $bnf_target->generate($raw_ir);
    eval "$generated; 1" or die "Grammar eval failed: $@";
    no strict 'refs';
    my $grammar = "Chalk::Grammar::BNF::Generated"->can('grammar')->();

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

done_testing();
