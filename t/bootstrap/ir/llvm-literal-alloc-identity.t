# ABOUTME: ArrayRef/HashRef literals are allocations: per-call identity so two
# ABOUTME: textually-identical literals are distinct mallocs, never one shared aggregate.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# An aggregate literal ALLOCATES (the Call(new) precedent: construction is
# an effect). Content hash-consing collapsed `[1,2]` and `[1,2]` to one
# node -> one malloc: a store through one "distinct" ref was visible
# through the other (019eb6ff item 4).

# Print the returned value on stdout, bracketed, instead of relying on a
# type-tag epilogue: rebuild the Return so the value flows through
# Coerce->Str into Prints hung off the graph's existing control chain.
# Three Prints (not a Concat) because Concat needs tracked lengths on both
# operands, which a Coerce'd Int does not have.
sub print_returned_value {
    my ($f, $ret_node) = @_;

    my $v = $ret_node->inputs->[0];
    my $s = $v;
    if (($v->representation // '') ne 'Str') {
        $s = $f->make('Coerce', inputs => [$v],
            from_repr => $v->representation, to_repr => 'Str');
        $s->set_representation('Str');
    }

    my $open = $f->make('Constant', value => '[', const_type => 'string');
    $open->set_representation('Str');
    my $close = $f->make('Constant', value => "]\n", const_type => 'string');
    $close->set_representation('Str');

    my $ctrl = $ret_node->control_in // $f->make_cfg('Start');
    for my $part ($open, $s, $close) {
        my $p = $f->make('Print', inputs => [$part]);
        $p->set_control_in($ctrl);
        $ctrl = $p;
    }

    my $u = $f->make('Constant', value => undef, const_type => 'undef');
    $u->set_representation('Undef');
    my $ret = $f->make_cfg('Return', inputs => [$u]);
    $ret->set_control_in($ctrl);
    return $ret;
}


sub run_lli {
    my ($ll) = @_;
    my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $ll;
    close $fh;
    my $out  = qx($LLI $tmp 2>&1);
    my $exit = $? >> 8;
    chomp $out;
    return ($out, $exit);
}

sub int_const {
    my ($f, $val) = @_;
    my $c = $f->make('Constant', value => "$val", const_type => 'integer');
    $c->set_representation('Int');
    return $c;
}

sub str_const {
    my ($f, $val) = @_;
    my $c = $f->make('Constant', value => $val, const_type => 'string');
    $c->set_representation('Str');
    return $c;
}

subtest 'aggregate constructors have per-call identity at the factory' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $one = int_const($f, 1);

    my $a1 = $f->make('ArrayLiteral', inputs => [$one]);
    my $a2 = $f->make('ArrayLiteral', inputs => [$one]);
    isnt($a1->id, $a2->id, 'identical ArrayRef literals are distinct nodes');

    my $k = str_const($f, 'k');
    my $h1 = $f->make('HashLiteral', inputs => [$k, $one]);
    my $h2 = $f->make('HashLiteral', inputs => [$k, $one]);
    isnt($h1->id, $h2->id, 'identical HashRef literals are distinct nodes');
};

# my $a = [1, 2]; my $b = [1, 2]; $b->[0] = 9; return $a->[0];
# perl: 1 — the two literals are distinct arrays; the store through $b
# must not be visible through $a.
subtest 'identical array literals do not alias' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my ($one_a, $two_a) = (int_const($f, 1), int_const($f, 2));
    my $lit_a = $f->make('ArrayLiteral', inputs => [$one_a, $two_a]);
    $lit_a->set_representation('ArrayRef');
    my $na = $f->make('Constant', value => '$a', const_type => 'string');
    my $va = $f->make('VarDecl', inputs => [$na, $lit_a]);
    $va->set_representation('ArrayRef');

    my $lit_b = $f->make('ArrayLiteral', inputs => [$one_a, $two_a]);
    $lit_b->set_representation('ArrayRef');
    isnt($lit_b->id, $lit_a->id, 'precondition: the two literals are distinct nodes');
    my $nb = $f->make('Constant', value => '$b', const_type => 'string');
    my $vb = $f->make('VarDecl', inputs => [$nb, $lit_b]);
    $vb->set_representation('ArrayRef');

    my $rb = $f->make('PadAccess', targ => 1, varname => '$b', inputs => [$vb]);
    $rb->set_representation('ArrayRef');
    my $store_lv = $f->make('Subscript', inputs => [$rb, int_const($f, 0)]);
    $store_lv->set_representation('Int');
    my $st = $f->make('Assign', inputs => [$store_lv, int_const($f, 9)]);
    $st->set_representation('Int');

    my $ra = $f->make('PadAccess', targ => 0, varname => '$a', inputs => [$va]);
    $ra->set_representation('ArrayRef');
    my $rd = $f->make('Subscript', inputs => [$ra, int_const($f, 0)]);
    $rd->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$rd]);
    $ret->set_control_in($st);
    $st->set_control_in($vb);
    $vb->set_control_in($va);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower(print_returned_value($f, $ret), program_mode => 1));
    is($exit, 0, 'lli exits 0');
    is($out, '[1]', 'the store through $b is invisible through $a (perl: 1)');
};

done_testing;
