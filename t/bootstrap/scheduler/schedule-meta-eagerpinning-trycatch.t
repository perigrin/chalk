# ABOUTME: Tests for Chalk::Scheduler::EagerPinning::TryCatch schedule_data.
# ABOUTME: Carries catch_var, try_stmts, catch_stmts set by TryStatement action.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Node;
use Chalk::Scheduler::EagerPinning::TryCatch;

my $try = Chalk::IR::Node->new(id => 'try_1');

# Defaults: empty arrays, undef catch_var.
my $bare = Chalk::Scheduler::EagerPinning::TryCatch->new(node => $try);
isa_ok($bare, 'Chalk::Scheduler::EagerPinning::TryCatch');
isa_ok($bare, 'Chalk::Scheduler::ScheduleMeta');
is($bare->catch_var, undef, 'catch_var defaults undef');
is_deeply($bare->try_stmts,   [], 'try_stmts defaults empty arrayref');
is_deeply($bare->catch_stmts, [], 'catch_stmts defaults empty arrayref');

# Populated.
my $stmt_a = Chalk::IR::Node->new(id => 'stmt_a');
my $stmt_b = Chalk::IR::Node->new(id => 'stmt_b');
my $full = Chalk::Scheduler::EagerPinning::TryCatch->new(
    node        => $try,
    catch_var   => '$e',
    try_stmts   => [$stmt_a],
    catch_stmts => [$stmt_b],
);
is($full->catch_var, '$e', 'catch_var preserved');
is_deeply($full->try_stmts,   [$stmt_a], 'try_stmts preserved');
is_deeply($full->catch_stmts, [$stmt_b], 'catch_stmts preserved');

done_testing();
