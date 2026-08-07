# ABOUTME: Tests that Chalk::Target::LLVM->lower(..., program_mode => 1) suppresses
# ABOUTME: the return-value type-tag epilogue printf while default lowering still emits it.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM;

# Same graph lowered twice: default (no opts) must still emit the Int:%lld
# epilogue printf (the corpus harness's return-value oracle depends on this
# staying on by default); program_mode => 1 must suppress it entirely while
# still emitting a correct `ret i32 0`.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c1 = $f->make('Constant', value => '2', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '3', const_type => 'integer');
    $c2->set_representation('Int');
    my $add = $f->make('Add', inputs => [$c1, $c2]);
    $add->set_representation('Int');

    my $ret_default = $f->make_cfg('Return', inputs => [$add]);
    my $ll_default  = Chalk::Target::LLVM->lower($ret_default);

    like($ll_default, qr/Int:%lld/,
        'default lowering (no program_mode) still emits the Int type-tag epilogue printf');

    my $ret_program = $f->make_cfg('Return', inputs => [$add]);
    my $ll_program  = Chalk::Target::LLVM->lower($ret_program, program_mode => 1);

    unlike($ll_program, qr/Int:%lld/,
        'program_mode => 1 suppresses the Int type-tag epilogue printf');
    unlike($ll_program, qr/call i32 \(i8\*, \.\.\.\) \@printf/,
        'program_mode => 1 emits no printf CALL at all for a bare Int return (the unconditional declare is harmless)');
    like($ll_program, qr/ret i32 0/,
        'program_mode => 1 still emits a correct ret instruction');
}

done_testing;
