# ABOUTME: Tests for Chalk::IR::Schedule and Chalk::IR::Schedule::Item shape.
# ABOUTME: Phase 2 — data types only, no producer; hand-built fixtures exercise the shape.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Node;
use Chalk::IR::Schedule;
use Chalk::IR::Schedule::Item;

# --- Item shape: { kind, node, form? } ---

# Simple statement: kind=stmt, node=ref, no form.
my $stmt_node = Chalk::IR::Node->new(id => 'call_1');
my $stmt = Chalk::IR::Schedule::Item->new(kind => 'stmt', node => $stmt_node);
isa_ok($stmt, 'Chalk::IR::Schedule::Item');
is($stmt->kind, 'stmt', 'kind is stmt');
is($stmt->node, $stmt_node, 'node ref preserved');
is($stmt->form, undef, 'form undef for stmt');

# Structural marker: block_open with form.
my $if_node = Chalk::IR::Node->new(id => 'if_1');
my $open = Chalk::IR::Schedule::Item->new(
    kind => 'block_open',
    node => $if_node,
    form => 'if',
);
is($open->kind, 'block_open', 'kind is block_open');
is($open->form, 'if',         'form is if');

# Else and elsif markers (no node, just kind).
my $else = Chalk::IR::Schedule::Item->new(kind => 'else');
is($else->kind, 'else', 'else item');
is($else->node, undef, 'else has no node');

# kind is required.
eval { Chalk::IR::Schedule::Item->new(node => $stmt_node) };
ok($@, 'missing kind dies') or diag("got: $@");

# --- Schedule shape: ordered list of items ---

my $schedule = Chalk::IR::Schedule->new(items => [$stmt]);
isa_ok($schedule, 'Chalk::IR::Schedule');
is_deeply([map { $_->kind } $schedule->items->@*], ['stmt'], 'items preserved');

# Empty schedule.
my $empty = Chalk::IR::Schedule->new(items => []);
is(scalar $empty->items->@*, 0, 'empty schedule has no items');

# items defaults to empty arrayref.
my $defaulted = Chalk::IR::Schedule->new;
is(scalar $defaulted->items->@*, 0, 'items defaults to empty');

# --- Open/close balance property ---

# Hand-build: if { stmt } - balanced.
my $sched_balanced = Chalk::IR::Schedule->new(items => [
    Chalk::IR::Schedule::Item->new(kind => 'block_open',  node => $if_node, form => 'if'),
    Chalk::IR::Schedule::Item->new(kind => 'stmt',        node => $stmt_node),
    Chalk::IR::Schedule::Item->new(kind => 'block_close', form => 'if'),
]);
ok($sched_balanced->is_balanced, 'simple if-block is balanced');

# Missing close: imbalanced.
my $sched_open = Chalk::IR::Schedule->new(items => [
    Chalk::IR::Schedule::Item->new(kind => 'block_open', node => $if_node, form => 'if'),
    Chalk::IR::Schedule::Item->new(kind => 'stmt',       node => $stmt_node),
]);
ok(!$sched_open->is_balanced, 'unclosed block is NOT balanced');

# Form mismatch: imbalanced.
my $loop_node = Chalk::IR::Node->new(id => 'loop_1');
my $sched_mismatch = Chalk::IR::Schedule->new(items => [
    Chalk::IR::Schedule::Item->new(kind => 'block_open',  node => $if_node, form => 'if'),
    Chalk::IR::Schedule::Item->new(kind => 'block_close', form => 'while'),
]);
ok(!$sched_mismatch->is_balanced, 'form mismatch is NOT balanced');

# Nested: if { while { stmt } } - balanced.
my $sched_nested = Chalk::IR::Schedule->new(items => [
    Chalk::IR::Schedule::Item->new(kind => 'block_open',  node => $if_node,   form => 'if'),
    Chalk::IR::Schedule::Item->new(kind => 'block_open',  node => $loop_node, form => 'while'),
    Chalk::IR::Schedule::Item->new(kind => 'stmt',        node => $stmt_node),
    Chalk::IR::Schedule::Item->new(kind => 'block_close', form => 'while'),
    Chalk::IR::Schedule::Item->new(kind => 'block_close', form => 'if'),
]);
ok($sched_nested->is_balanced, 'nested blocks are balanced');

# if { stmt } else { stmt } - balanced; else is interior.
my $sched_if_else = Chalk::IR::Schedule->new(items => [
    Chalk::IR::Schedule::Item->new(kind => 'block_open',  node => $if_node, form => 'if'),
    Chalk::IR::Schedule::Item->new(kind => 'stmt',        node => $stmt_node),
    Chalk::IR::Schedule::Item->new(kind => 'else'),
    Chalk::IR::Schedule::Item->new(kind => 'stmt',        node => $stmt_node),
    Chalk::IR::Schedule::Item->new(kind => 'block_close', form => 'if'),
]);
ok($sched_if_else->is_balanced, 'if/else is balanced');

# Stray close (no matching open) - imbalanced.
my $sched_stray = Chalk::IR::Schedule->new(items => [
    Chalk::IR::Schedule::Item->new(kind => 'block_close', form => 'if'),
]);
ok(!$sched_stray->is_balanced, 'stray close is NOT balanced');

done_testing();
