# ABOUTME: Batch G CFG harness tests — I1 (ADJUST block).
# ABOUTME: Documents I1 as NOT-YET-COVERED: emitter has no ADJUST block emission support.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::CodeGen::Harness::HandGraphs;
use Chalk::Bootstrap::Perl::Target::Perl;

# I1: class C { field $x :param; ADJUST { $x = $x + 1; } method m() { return $x; } }
#
# ADJUST block emission is not yet implemented in Target::Perl::_emit_mop_class.
# The emitter only walks fields, methods, and subs — it does not call
# $cls->adjust_blocks() or emit the ADJUST { ... } body.
# Missing machinery:
#   lib/Chalk/Bootstrap/Perl/Target/Perl.pm _emit_mop_class
#   needs: walk cls->adjust_blocks, schedule each block's graph, emit ADJUST { body }
#
# This test documents the gap and will need updating when I1 is implemented.

ok(!defined(Chalk::CodeGen::Harness::HandGraphs->graph_for('I1')),
   'I1 has no hand graph — correctly NOT-YET-COVERED');

pass('I1 is NOT-YET-COVERED: ADJUST block emission not implemented in _emit_mop_class');

done_testing();
