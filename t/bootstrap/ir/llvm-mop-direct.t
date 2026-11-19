# ABOUTME: The LLVM backend builds its class registry from a sealed Chalk::MOP directly
# ABOUTME: (lower(mop => $mop) + Call.class_name) — no ClassInfo metadata rides the graph.
use 5.42.0;
use utf8;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);
use Chalk::CodeGen::Harness::Rooted qw(rooted body reader);

use Chalk::IR::Graph;
use Chalk::MOP;
use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM;

use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;


# docs/plans/2026-06-11-llvm-reads-mop-directly.md: class structure is
# compile-time context. The backend receives the sealed MOP alongside the
# graph and resolves Call.class_name against a registry built from
# MOP::Class/Method/Field/Phaser::Adjust — the ClassInfo bridge retires.

# Print the returned value on stdout, bracketed, instead of relying on a
# type-tag epilogue: rebuild the Return so the value flows through
# Coerce->Str into Prints hung off the graph's existing control chain.
# Three Prints (not a Concat) because Concat needs tracked lengths on both
# operands, which a Coerce'd Int does not have.
sub print_returned_value {
    my ($f, $ret_node) = @_;

    my $v = $ret_node->inputs->[0];
    my $s = $v;
    if (($v->stamp // '') ne 'Str') {
        $s = $f->make('Coerce', inputs => [$v],
            from_repr => $v->stamp, to_repr => 'Str');
        $s->set_stamp('Str');
    }

    my $open = $f->make('Constant', value => '[', const_type => 'string');
    $open->set_stamp('Str');
    my $close = $f->make('Constant', value => "]\n", const_type => 'string');
    $close->set_stamp('Str');

    my $ctrl = $ret_node->control_in // $f->make_cfg('Start');
    for my $part ($open, $s, $close) {
        my $p = $f->make('Print', inputs => [$part]);
        $p->set_control_in($ctrl);
        $ctrl = $p;
    }

    my $u = $f->make('Constant', value => undef, const_type => 'undef');
    $u->set_stamp('Undef');
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
    $c->set_stamp('Int');
    return $c;
}

# class Pt { field $x :param :reader; field $y;
#            ADJUST { $y = $x + 1 }
#            method val { $y } }
# my $p = Pt->new(x => 5); return $p->val + $p->x;  => perl: 6 + 5 = 11
subtest 'field + reader + ADJUST + method via the sealed MOP' => sub {
    my $f   = Chalk::IR::NodeFactory->new;
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Pt', is_class => 1);

    $cls->declare_field('x', sigil => '$', type => 'Int',
        attributes => [':param', ':reader'], param_name => 'x');

    reader($cls, 'x');   # (the reader method B::SoN gives the class)
    $cls->declare_field('y', sigil => '$', type => 'Int', attributes => []);

    # method val { $y }
    my $fa_y = $f->make('FieldAccess', field_index => 1, field_stash => 'Pt', inputs => []);
    $fa_y->set_stamp('Int');
    my $m = $cls->declare_method('val', graph => Chalk::IR::Graph->new, return_type => 'Int');
    $m->graph->merge($f->make_cfg('Return', inputs => [$fa_y]));

    # ADJUST { $y = $x + 1 }
    my $fa_x = $f->make('FieldAccess', field_index => 0, field_stash => 'Pt', inputs => []);
    $fa_x->set_stamp('Int');
    my $add = $f->make('Add', inputs => [$fa_x, int_const($f, 1)]);
    $add->set_stamp('Int');
    my $fa_y_lv = $f->make('FieldAccess', field_index => 1, field_stash => 'Pt', inputs => []);
    $fa_y_lv->set_stamp('Int');
    my $st = $f->make('Assign', inputs => [$fa_y_lv, $add]);
    $st->set_stamp('Int');
    my $adj = $cls->declare_adjust(graph => Chalk::IR::Graph->new);
    body($adj->graph, $st);

    $mop->seal;

    my $new = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Pt', param_names => ['x'], inputs => [int_const($f, 5)]);
    $new->set_stamp('Object');
    my $val = $f->make('Call', dispatch_kind => 'method', name => 'val',
        class_name => 'Pt', inputs => [$new]);
    $val->set_stamp('Int');
    my $x = $f->make('Call', dispatch_kind => 'method', name => 'x',
        class_name => 'Pt', inputs => [$new]);
    $x->set_stamp('Int');
    my $sum = $f->make('Add', inputs => [$val, $x]);
    $sum->set_stamp('Int');
    my $ret = $f->make_cfg('Return', inputs => [$sum]);

    my $ll = Chalk::Target::LLVM->lower(rooted(print_returned_value($f, $ret), $mop), mop => $mop, program_mode => 1);
    unlike($ll, qr/\bSV\b|Perl_|libperl/, '.ll is libperl-free');
    my ($out, $exit) = run_lli($ll);
    is($exit, 0, 'lli exits 0');
    is($out, '[11]', 'ADJUST + method + :reader all dispatch (perl: 6+5=11)');
};

# class Base { method seven { 7 } }  class Kid :isa(Base) {}
# return Kid->new->seven;  => perl: 7
subtest ':isa inheritance through the MOP registry' => sub {
    my $f   = Chalk::IR::NodeFactory->new;
    my $mop = Chalk::MOP->new;

    my $base = $mop->declare_class('Base', is_class => 1);
    my $bm = $base->declare_method('seven', graph => Chalk::IR::Graph->new, return_type => 'Int');
    $bm->graph->merge($f->make_cfg('Return', inputs => [int_const($f, 7)]));

    $mop->declare_class('Kid', parent_name => 'Base', is_class => 1);

    $mop->seal;

    my $new = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Kid', inputs => []);
    $new->set_stamp('Object');
    my $call = $f->make('Call', dispatch_kind => 'method', name => 'seven',
        class_name => 'Kid', inputs => [$new]);
    $call->set_stamp('Int');
    my $ret = $f->make_cfg('Return', inputs => [$call]);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower(rooted(print_returned_value($f, $ret), $mop), mop => $mop, program_mode => 1));
    is($exit, 0, 'lli exits 0');
    is($out, '[7]', 'inherited method dispatches through the child vtable (perl: 7)');
};

# Multi-statement ADJUST bodies are ordered by their control chain.
# ADJUST { $p = $x; $x = 9; $q = $x }  =>  p=5, q=9, val: p+q = 14
subtest 'multi-statement ADJUST body in control-chain order' => sub {
    my $f   = Chalk::IR::NodeFactory->new;
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Pt', is_class => 1);

    $cls->declare_field('x', sigil => '$', type => 'Int', attributes => [':param'], param_name => 'x');
    $cls->declare_field('p', sigil => '$', type => 'Int', attributes => []);
    $cls->declare_field('q', sigil => '$', type => 'Int', attributes => []);

    my $fa_x = $f->make('FieldAccess', field_index => 0, field_stash => 'Pt', inputs => [$f->make('MemStart')]);
    $fa_x->set_stamp('Int');
    my $fa_p_lv = $f->make('FieldAccess', field_index => 1, field_stash => 'Pt', inputs => []);
    $fa_p_lv->set_stamp('Int');
    my $fa_q_lv = $f->make('FieldAccess', field_index => 2, field_stash => 'Pt', inputs => []);
    $fa_q_lv->set_stamp('Int');

    my $st_p = $f->make('Assign', inputs => [$fa_p_lv, $fa_x]);
    $st_p->set_stamp('Int');
    my $st_x = $f->make('Assign',
        inputs => [$f->make('FieldAccess', field_index => 0, field_stash => 'Pt', inputs => []), int_const($f, 9)]);
    $st_x->set_stamp('Int');
    # A READ OF $x AFTER THE STORE is a read of its own, at the store's memory
    # (B::SoN's: the first read is at MemStart, this one at the Assign).
    my $fa_x_after = $f->make('FieldAccess', field_index => 0, field_stash => 'Pt', inputs => [$st_x]);
    $fa_x_after->set_stamp('Int');
    my $st_q = $f->make('Assign', inputs => [$fa_q_lv, $fa_x_after]);
    $st_q->set_stamp('Int');

    # Thread the body order: st_p -> st_x -> st_q.
    $st_x->set_control_in($st_p);
    $st_q->set_control_in($st_x);

    my $adj = $cls->declare_adjust(graph => Chalk::IR::Graph->new);
    body($adj->graph, $st_p, $st_x, $st_q);

    my $fa_p = $f->make('FieldAccess', field_index => 1, field_stash => 'Pt', inputs => []);
    $fa_p->set_stamp('Int');
    my $fa_q = $f->make('FieldAccess', field_index => 2, field_stash => 'Pt', inputs => []);
    $fa_q->set_stamp('Int');
    my $body = $f->make('Add', inputs => [$fa_p, $fa_q]);
    $body->set_stamp('Int');
    my $m = $cls->declare_method('val', graph => Chalk::IR::Graph->new, return_type => 'Int');
    $m->graph->merge($f->make_cfg('Return', inputs => [$body]));

    $mop->seal;

    my $new = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Pt', param_names => ['x'], inputs => [int_const($f, 5)]);
    $new->set_stamp('Object');
    my $val = $f->make('Call', dispatch_kind => 'method', name => 'val',
        class_name => 'Pt', inputs => [$new]);
    $val->set_stamp('Int');
    my $ret = $f->make_cfg('Return', inputs => [$val]);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower(rooted(print_returned_value($f, $ret), $mop), mop => $mop, program_mode => 1));
    is($exit, 0, 'lli exits 0');
    is($out, '[14]', 'statements ran in chain order (perl: 5 + 9 = 14)');
};

# class Top { method seven { 7 } } class Mid :isa(Top) {} class Kid :isa(Mid) {}
# return Kid->new->seven;  => perl: 7.  Class names chosen so the GRANDCHILD
# sorts before its parent ("Kid" lt "Mid") — a single-pass flatten over
# sorted names copies Mid's methods into Kid before Mid has inherited Top's.
subtest 'grandparent inheritance, child sorts before parent (review)' => sub {
    my $f   = Chalk::IR::NodeFactory->new;
    my $mop = Chalk::MOP->new;

    my $top = $mop->declare_class('Top', is_class => 1);
    my $tm = $top->declare_method('seven', graph => Chalk::IR::Graph->new, return_type => 'Int');
    $tm->graph->merge($f->make_cfg('Return', inputs => [int_const($f, 7)]));

    $mop->declare_class('Mid', parent_name => 'Top', is_class => 1);
    $mop->declare_class('Kid', parent_name => 'Mid', is_class => 1);

    $mop->seal;

    my $new = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Kid', inputs => []);
    $new->set_stamp('Object');
    my $call = $f->make('Call', dispatch_kind => 'method', name => 'seven',
        class_name => 'Kid', inputs => [$new]);
    $call->set_stamp('Int');
    my $ret = $f->make_cfg('Return', inputs => [$call]);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower(rooted(print_returned_value($f, $ret), $mop), mop => $mop, program_mode => 1));
    is($exit, 0, 'lli exits 0');
    is($out, '[7]', 'the grandparent method reaches the grandchild vtable (perl: 7)');
};

# field $y = 41 (default, no :param): the default-value lowering path
# through MOP::Field->default_value. perl: 41.
subtest 'field default value lowers through the MOP registry (review)' => sub {
    my $f   = Chalk::IR::NodeFactory->new;
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Dft', is_class => 1);

    my $c41 = int_const($f, 41);
    $cls->declare_field('y', sigil => '$', type => 'Int', attributes => [],
        has_default => true, default_value => $c41);

    my $fa_y = $f->make('FieldAccess', field_index => 0, field_stash => 'Dft', inputs => []);
    $fa_y->set_stamp('Int');
    my $m = $cls->declare_method('val', graph => Chalk::IR::Graph->new, return_type => 'Int');
    $m->graph->merge($f->make_cfg('Return', inputs => [$fa_y]));

    $mop->seal;

    my $new = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Dft', inputs => []);
    $new->set_stamp('Object');
    my $val = $f->make('Call', dispatch_kind => 'method', name => 'val',
        class_name => 'Dft', inputs => [$new]);
    $val->set_stamp('Int');
    my $ret = $f->make_cfg('Return', inputs => [$val]);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower(rooted(print_returned_value($f, $ret), $mop), mop => $mop, program_mode => 1));
    is($exit, 0, 'lli exits 0');
    is($out, '[41]', 'the default expression initializes the field (perl: 41)');
};

subtest 'guards: an unsealed MOP, and a called method with no Return or two, are refused by name' => sub {
    # A PROGRAM THAT CALLS Pt->new->val and prints it: T2 builds a method
    # only where it is called, so each malformed method is called.
    my $calls_val = sub ($f, $mop) {
        my $new = $f->make('Call', dispatch_kind => 'method', name => 'new',
            class_name => 'Pt', param_names => [], inputs => []);
        $new->set_stamp('Object');
        my $val = $f->make('Call', dispatch_kind => 'method', name => 'val',
            class_name => 'Pt', inputs => [$new]);
        $val->set_stamp('Int');
        return rooted(print_returned_value($f, $f->make_cfg('Return', inputs => [$val])), $mop);
    };
    my $refused = sub ($mop, $f, $why, $name) {
        my $ll = eval { Chalk::Target::LLVM->lower($calls_val->($f, $mop), mop => $mop) };
        ok(!defined $ll, "$name: T2 lowers no module for it");
        like($@, qr/GAP: T2: out of its slices \(\Q$why\E\)/, "$name: refused by T2's reason");
    };

    my $f   = Chalk::IR::NodeFactory->new;
    my $mop = Chalk::MOP->new;
    $mop->declare_class('Pt')->declare_method('val', graph => Chalk::IR::Graph->new, return_type => 'Int')
        ->graph->merge($f->make_cfg('Return', inputs => [int_const($f, 1)]));
    $refused->($mop, $f, 'an unsealed MOP', 'an unsealed MOP');

    my $f2   = Chalk::IR::NodeFactory->new;
    my $mop2 = Chalk::MOP->new;
    $mop2->declare_class('Pt')->declare_method('val', graph => Chalk::IR::Graph->new, return_type => 'Int');   # graph has no Return
    $mop2->seal;
    $refused->($mop2, $f2, 'sub Pt::val has no Return', 'a method graph without a Return');

    # MULTIPLE Returns: Graph::returns() iterates a hash, so picking "the
    # first" is nondeterministic -- the contract is exactly one (review).
    my $f3   = Chalk::IR::NodeFactory->new;
    my $mop3 = Chalk::MOP->new;
    my $m3   = $mop3->declare_class('Pt')->declare_method('val', graph => Chalk::IR::Graph->new, return_type => 'Int');
    $m3->graph->merge($f3->make_cfg('Return', inputs => [int_const($f3, 1)]));
    $m3->graph->merge($f3->make_cfg('Return', inputs => [int_const($f3, 2)]));
    $mop3->seal;
    $refused->($mop3, $f3, 'sub Pt::val has more than one Return', 'a method graph with two Returns');

    # A class_name Call lowered WITHOUT a mop is refused -- the deleted
    # ClassInfo bridge does not silently revive.
    my $f4 = Chalk::IR::NodeFactory->new;
    my $ghost = $f4->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Ghost', inputs => []);
    $ghost->set_stamp('Object');
    my $ll4 = eval { Chalk::Target::LLVM->lower(rooted($f4->make_cfg('Return', inputs => [$ghost]))) };
    ok(!defined $ll4, 'a class_name Call without a mop: T2 lowers no module for it');
    like($@, qr/GAP: T2: out of its slices \(a method call with no MOP\)/, "a class_name Call without a mop: refused by T2's reason");
};

done_testing;
