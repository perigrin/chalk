# ABOUTME: Roots a hand-built test graph at a Start, as every graph B::SoN produces is: the head of
# ABOUTME: its control chain (and of each MOP method's) takes a Start, so T2 can walk back to it.
package Chalk::CodeGen::Harness::Rooted;
use v5.42.0;
use Scalar::Util qw(blessed refaddr);
use Exporter 'import';
use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;
our @EXPORT_OK = qw(rooted body reader);

# rooted($ret, $mop?) -> $ret
#
# A fixture written before graphs began at a Start ends its control chain at a
# node with no control input: a Print, an Assign, a VarDecl, the Return itself.
# T2 refuses that shape ("no way back to Start"), which is a fact about the
# fixture, not about the program it spells. This gives the chain the Start it
# lacks, walking back as T2 walks (a control input, else a Region's or a
# Proj's first input) -- and does the same for each method graph of $mop.
# A chain that already begins at a Start is left as it is.
sub rooted ($ret, $mop = undef) {
    _root($ret);
    if ($mop) {
        for my $c ($mop->classes) {
            for my $m ( ( $c->can('methods') ? $c->methods : () ), ( $c->can('subs') ? $c->subs : () ),
                        ( $c->can('adjust_blocks') ? $c->adjust_blocks : () ) ) {
                my $g = $m->can('graph') ? $m->graph : undef;
                next unless blessed($g) && $g->can('returns');
                _root($_) for grep { blessed($_) } ( $g->returns // [] )->@*;
            }
        }
    }
    return $ret;
}

# body($graph, @statements) -> $graph
#
# A hand-built phaser or method body: its statements in the order given, from a
# Start, ended by a Return of undef -- the shape B::SoN gives a body. (merge()
# alone records no order: a graph's nodes are a hash.)
sub body ($graph, @statements) {
    my $f    = Chalk::IR::NodeFactory->new;
    my $prev = $f->make('Start');
    for my $st (@statements) { $st->set_control_in($prev); $graph->merge($st); $prev = $st }
    my $u = $f->make('Constant', value => undef, const_type => 'undef');
    $u->set_stamp('Undef');
    my $ret = $f->make_cfg('Return', inputs => [$u]);
    $ret->set_control_in($prev);
    $graph->merge($ret);
    return $graph;
}

# reader($cls, $field_name, $method_name?) -> the method
#
# A :reader field's method, as B::SoN gives it: a graph of its own, Start to a
# Return of the field's value (FieldAccess at its index). A fixture that only
# declares the attribute has a class with no such method.
sub reader ($cls, $field_name, $method_name = $field_name) {
    my ($fld) = grep { $_->name eq $field_name } $cls->fields;
    die "reader: $field_name is no field of " . $cls->name . "\n" unless $fld;
    my $f  = Chalk::IR::NodeFactory->new;
    my $fa = $f->make('FieldAccess', field_index => $fld->fieldix, field_stash => $cls->name, inputs => []);
    $fa->set_stamp($fld->can('type') && defined $fld->type ? $fld->type : 'Scalar');
    my $ret = $f->make_cfg('Return', inputs => [$fa]);
    $ret->set_control_in($f->make('Start'));
    my $m = $cls->declare_method($method_name, graph => Chalk::IR::Graph->new, return_type => $fa->stamp);
    $m->graph->merge($ret);
    return $m;
}

sub _root ($n) {
    _pin_literals($n);
    my %seen;
    while ( blessed($n) && !$seen{ refaddr($n) }++ ) {
        return if $n->operation eq 'Start';
        if ( $n->can('control_in') && blessed( $n->control_in ) ) { $n = $n->control_in; next }
        if ( $n->operation =~ /\A(?:Region|Proj)\z/ ) { $n = $n->inputs->[0]; next }
        $n->set_control_in( Chalk::IR::NodeFactory->new->make('Start') );
        return;
    }
}

# _pin_literals($ret): an anonymous array or hash is made where it stands, on
# the control chain just before the first statement that reads it -- where
# B::SoN puts it. A fixture's floats (no control input); each found among a
# chain statement's inputs is put there.
sub _pin_literals ($ret) {
    my (@chain, %seen);
    for (my $n = $ret; blessed($n) && !$seen{ refaddr($n) }++; $n = $n->can('control_in') ? $n->control_in : undef) {
        unshift @chain, $n;
    }
    my %on = map { ( refaddr($_) => 1 ) } @chain;
    my %pinned;
    for my $st (@chain) {
        my (@lits, %v);
        my @q = grep { blessed($_) } $st->inputs->@*;
        while (defined( my $v = shift @q )) {
            next if $v{ refaddr($v) }++ || $on{ refaddr($v) };
            if ( $v->operation =~ /\A(?:ArrayLiteral|HashLiteral)\z/ && !blessed( $v->control_in ) && !$pinned{ refaddr($v) }++ ) {
                push @lits, $v;
            }
            push @q, grep { blessed($_) } $v->inputs->@*;
        }
        # innermost first: a literal inside another is made before it
        for my $lit (reverse @lits) {
            $lit->set_control_in( $st->control_in );
            $st->set_control_in($lit);
        }
    }
}

1;
