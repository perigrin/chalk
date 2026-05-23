# ABOUTME: Tests for Chalk::Scheduler::Roundtrip::If schedule_data.
# ABOUTME: Carries is_loop_jump set by PostfixModifier action for `next if` / `last unless`.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Node;
use Chalk::Scheduler::Roundtrip::If;

my $node = Chalk::IR::Node->new(id => 'if_1');

# Default: plain If, no loop-jump shortcut.
my $plain = Chalk::Scheduler::Roundtrip::If->new(node => $node);
isa_ok($plain, 'Chalk::Scheduler::Roundtrip::If');
isa_ok($plain, 'Chalk::Scheduler::ScheduleMeta');
is($plain->is_loop_jump, undef, 'is_loop_jump defaults undef');

# Loop-jump form: carries the jump keyword.
my $next = Chalk::Scheduler::Roundtrip::If->new(
    node          => $node,
    is_loop_jump => 'next',
);
is($next->is_loop_jump, 'next', 'next-if preserves the keyword');

my $last = Chalk::Scheduler::Roundtrip::If->new(
    node          => $node,
    is_loop_jump => 'last',
);
is($last->is_loop_jump, 'last', 'last-if preserves the keyword');

done_testing();
