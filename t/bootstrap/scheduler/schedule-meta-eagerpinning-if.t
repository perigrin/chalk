# ABOUTME: Tests for Chalk::Scheduler::EagerPinning::If schedule_data.
# ABOUTME: Carries is_loop_jump set by PostfixModifier action for `next if` / `last unless`.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Node;
use Chalk::Scheduler::EagerPinning::If;

my $node = Chalk::IR::Node->new(id => 'if_1');

# Default: plain If, no loop-jump shortcut.
my $plain = Chalk::Scheduler::EagerPinning::If->new(node => $node);
isa_ok($plain, 'Chalk::Scheduler::EagerPinning::If');
isa_ok($plain, 'Chalk::Scheduler::ScheduleMeta');
is($plain->is_loop_jump, undef, 'is_loop_jump defaults undef');

# Loop-jump form: carries the jump keyword.
my $next = Chalk::Scheduler::EagerPinning::If->new(
    node          => $node,
    is_loop_jump => 'next',
);
is($next->is_loop_jump, 'next', 'next-if preserves the keyword');

my $last = Chalk::Scheduler::EagerPinning::If->new(
    node          => $node,
    is_loop_jump => 'last',
);
is($last->is_loop_jump, 'last', 'last-if preserves the keyword');

# Branch-body fields default empty / undef.
is_deeply($plain->then_stmts, [], 'then_stmts defaults []');
is($plain->else_stmts, undef, 'else_stmts defaults undef (distinguishes "no else" from "empty else")');

# Populated then/else.
my $a = Chalk::IR::Node->new(id => 'a');
my $b = Chalk::IR::Node->new(id => 'b');
my $with_arms = Chalk::Scheduler::EagerPinning::If->new(
    node       => $node,
    then_stmts => [$a],
    else_stmts => [$b],
);
is_deeply($with_arms->then_stmts, [$a], 'then_stmts preserved');
is_deeply($with_arms->else_stmts, [$b], 'else_stmts preserved');

# If with then but no else.
my $no_else = Chalk::Scheduler::EagerPinning::If->new(
    node       => $node,
    then_stmts => [$a],
);
is_deeply($no_else->then_stmts, [$a], 'then-only: then_stmts preserved');
is($no_else->else_stmts, undef, 'then-only: else_stmts undef');

done_testing();
