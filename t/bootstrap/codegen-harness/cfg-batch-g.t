# ABOUTME: Batch G CFG harness tests — I1 (ADJUST block).
# ABOUTME: Verifies I1 PASS: ADJUST block is emitted and its side-effect is observable.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness::HandGraphs;
use Chalk::CodeGen::Harness;

# I1: class C { field $x :param; ADJUST { $x = $x + 1; } method m() { return $x; } }
#
# The ADJUST block runs at construction time and increments $x.
# Constructing C->new(x => 5) then calling m() returns 6 (not 5),
# proving the ADJUST block fired and mutated the field.
#
# Implements:
#   - HandGraphs::_build_I1: ADJUST phaser graph + field + method m()
#   - Target::Perl::_emit_mop_adjust: walks cls->adjust_blocks, emits ADJUST { body }
#   - Target::Perl::_emit_mop_class: calls _emit_mop_adjust after fields

ok(defined(Chalk::CodeGen::Harness::HandGraphs->graph_for('I1')),
   'I1 has a hand graph — ADJUST block is implemented');

my $spec = {
    class       => 'C',
    constructor => { params => { x => 5 } },
    method      => 'm',
    method_args => [],
    context     => 'scalar',
};

my $result = eval { Chalk::CodeGen::Harness->run_entry('I1', $spec) };
ok(!$@, 'I1: run_entry does not die') or diag("Error: $@");
SKIP: {
    skip 'run_entry died', 2 if $@;
    my $verdict = $result->{verdict}{verdict} // $result->{verdict};
    is($verdict, 'PASS', 'I1: verdict is PASS (ADJUST emitted, S=P)');
    my $retval = $result->{P}->return_values->[0];
    is($retval, 6, 'I1: returns 6 (ADJUST incremented $x from 5 to 6)');
}

done_testing();
