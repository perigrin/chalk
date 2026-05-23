# ABOUTME: Tests for Chalk::Scheduler::EagerPinning::Phi schedule_data.
# ABOUTME: Carries emit_slot — the VarDecl whose surface identifier this Phi resolves to.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Node;
use Chalk::Scheduler::EagerPinning::Phi;

my $phi     = Chalk::IR::Node->new(id => 'phi_1');
my $vardecl = Chalk::IR::Node->new(id => 'vardecl_1');

# Default: emit_slot undef (scheduler falls back to synthetic $_phi_<id>).
my $bare = Chalk::Scheduler::EagerPinning::Phi->new(node => $phi);
isa_ok($bare, 'Chalk::Scheduler::EagerPinning::Phi');
isa_ok($bare, 'Chalk::Scheduler::ScheduleMeta');
is($bare->emit_slot, undef, 'emit_slot defaults undef');

# Slot resolved: Phi-slot maps to a specific VarDecl.
my $resolved = Chalk::Scheduler::EagerPinning::Phi->new(
    node      => $phi,
    emit_slot => $vardecl,
);
is($resolved->emit_slot, $vardecl, 'emit_slot preserved');

done_testing();
