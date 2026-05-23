# ABOUTME: Verifies PostfixModifier+ExpressionStatement populates EagerPinning::If on If.
# ABOUTME: Migration 2 of Phase 1 — moves loop_jump annotation from Context onto IR.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::IR::Node::If;
use Chalk::Scheduler::EagerPinning::If;
use Chalk::Bootstrap::BNF::Target::Perl;

my $ir = perl_pipeline();
plan skip_all => 'Perl grammar failed' unless defined $ir;

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ScheduleDataLoopJumpTest/g;
eval $generated;
plan skip_all => "Generated code failed: $@" if $@;

my $gen_grammar = Chalk::Grammar::Perl::ScheduleDataLoopJumpTest::grammar();
my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
plan skip_all => 'IR parser not built' unless defined $parser;

my $semiring = $parser->semiring();

# Helper: walk a sem-context tree pulling out every If node we can find
# whose schedule_data has is_loop_jump populated. Returns the list.
sub _collect_loop_jump_ifs($ctx) {
    my @out;
    my @stack = ($ctx);
    my %seen;
    while (@stack) {
        my $node = pop @stack;
        my $focus = $node->extract();
        if (defined $focus && ref($focus)
                && $focus isa Chalk::IR::Node::If
                && !$seen{refaddr $focus}++) {
            my $sd = $focus->schedule_data;
            if (defined $sd && $sd isa Chalk::Scheduler::EagerPinning::If
                    && defined $sd->is_loop_jump) {
                push @out, $focus;
            }
        }
        push @stack, $node->children()->@*;
    }
    return @out;
}
use Scalar::Util qw(refaddr);

# --- Test 1: `next if $cond;` ---
{
    $semiring->reset_cache();
    my $src = 'for my $x (1, 2, 3) { next if $x; }';
    my $result = $parser->parse_value($src);
    ok(defined $result, '`next if` parses');

    my @jumps = _collect_loop_jump_ifs($result);
    ok(scalar(@jumps) >= 1, 'at least one If with loop_jump schedule_data')
        or diag('no EagerPinning::If with is_loop_jump found');

    my $next_if = $jumps[0];
    is($next_if->schedule_data->is_loop_jump, 'next',
        'is_loop_jump = "next" for `next if`');
}

# --- Test 2: `last unless $cond;` ---
{
    $semiring->reset_cache();
    my $src = 'for my $x (1, 2, 3) { last unless $x; }';
    my $result = $parser->parse_value($src);
    ok(defined $result, '`last unless` parses');

    my @jumps = _collect_loop_jump_ifs($result);
    ok(scalar(@jumps) >= 1, 'at least one If with loop_jump schedule_data');

    my $last_if = $jumps[0];
    is($last_if->schedule_data->is_loop_jump, 'last',
        'is_loop_jump = "last" for `last unless`');
}

# --- Test 3: plain postfix-if is NOT a loop_jump ---
{
    $semiring->reset_cache();
    my $src = 'my $x = 0; $x = 1 if $x;';
    my $result = $parser->parse_value($src);
    ok(defined $result, 'plain `if` modifier parses');

    my @jumps = _collect_loop_jump_ifs($result);
    is(scalar(@jumps), 0, 'no loop_jump for plain postfix-if');
}

done_testing();
