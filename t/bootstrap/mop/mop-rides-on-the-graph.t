# ABOUTME: The MOP is an edge that exists on EVERY load, not only on class programs.
# ABOUTME: Pins the MOP edge -- on every load, on every graph, and on every method-dispatch Call.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use Scalar::Util qw(refaddr blessed);
use JSON::PP;
use feature 'try';
no warnings 'experimental::try';
use lib 'lib', 't/lib';
use Chalk::IR::Serialize::JSON;

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";

plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;
plan skip_all => "perl5-son not found at $SON"  unless -f "$SON/B/SoN.pm";

my $dir = tempdir(CLEANUP => 1);

sub load ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $json = qx{$PERL -I$SON -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
    # The MOP comes off a GRAPH, not off a second return slot -- that is the
    # property the subtests below assert, so the helper must not smuggle it in
    # by another route. Sorted for a deterministic choice of graph.
    my $mop = %$graphs ? $graphs->{ (sort keys %$graphs)[0] }->mop : undef;
    return ($graphs, $mop);
}

# A program with no classes and no named subs makes the producer emit
# `classes: undef`. The loader used to take that as "there is nothing to build a
# MOP from" and skip the replay, so a caller asking for the MOP got undef -- an
# edge that exists for some programs and not others. Every program has a `main`,
# so every load has a MOP, reachable from any graph it produced.
subtest 'a class-less program still yields a MOP' => sub {
    my ($graphs, $mop) = load('my $x = 1 + 2; print $x, "\n";', 'classless');
    ok defined $graphs, 'the graphs came back' or return;
    ok defined $mop, 'and so did the MOP';
    isa_ok $mop, 'Chalk::MOP';
};

# The MOP is reached through an EDGE on the IR, not through a second return
# value threaded alongside it. Every graph in a load points at the SAME sealed
# MOP -- one program, one metaobject universe -- so a pass holding only a graph
# can still reach the whole program.
subtest 'every graph carries the run MOP' => sub {
    my ($graphs, $mop) = load('my $x = 1 + 2; print $x, "\n";', 'graph_mop');
    ok defined $mop, 'the run has a MOP' or return;
    ok keys %$graphs, 'and at least one graph' or return;
    for my $name (sort keys %$graphs) {
        is refaddr($graphs->{$name}->mop), refaddr($mop),
            "graph $name carries the run MOP";
    }
};


# Spec §2: a transform holding one graph reaches the whole program through
# EDGES. A method-dispatch Call must therefore carry its callee METAOBJECT on
# `target`, exactly as a direct sub Call already does -- not a class-name
# string that every consumer re-resolves by scanning.
subtest 'a method-dispatch Call targets its MOP::Method' => sub {
    my ($graphs, $mop) = load(<<'SRC', 'method_target');
use experimental 'class';
class Base  { method m   { return 7 } }
class Child :isa(Base) { method own { return 3 } }
my $c = Child->new;
print $c->m + $c->own, "\n";
SRC

    my %call;
    for my $g (values %$graphs) {
        for my $n ($g->nodes->@*) {
            next unless blessed($n) && $n->operation eq 'Call';
            next unless ($n->dispatch_kind // '') eq 'method';
            $call{ $n->name // '?' } = $n;
        }
    }

    ok $call{own}, 'found the Child::own call' or return;
    isa_ok $call{own}->target, 'Chalk::MOP::Method', 'own target';
    is $call{own}->target->name, 'own', 'own resolves to own';
    is $call{own}->target->class->name, 'Child', 'own resolves on Child';
    is $call{own}->target->return_type, 'Int', 'own carries the wire return type';

    # The INHERITED call. `$c->m` names class Child, but Child has no `m` --
    # only Base does. Resolution must walk the superclass chain (MOP::Class's
    # own find_method), not scan the class table for a name match.
    ok $call{m}, 'found the inherited call' or return;
    isa_ok $call{m}->target, 'Chalk::MOP::Method', 'inherited target';
    is $call{m}->target->name, 'm', 'inherited resolves to m';
    is $call{m}->target->class->name, 'Base',
        'inherited resolves onto the DECLARING class, not the calling one';
    is $call{m}->target->return_type, 'Int',
        'inherited carries the wire return type';

    # And the edge is LOAD-BEARING, not decoration: the repr stamped on each
    # Call is the one resolved through it.
    is $call{own}->stamp, 'Int', 'own is stamped through the edge';
    is $call{m}->stamp, 'Int',   'inherited is stamped through the edge';
};

# A `:reader` accessor is synthesized by the backend, so no MOP::Method exists
# for it and the Call is legitimately target-less. It is still INHERITED, and it
# still needs its repr. This pins the fallback that resolution-through-the-edge
# must not eat: a reader declared on Base, called on Child.
subtest 'an inherited :reader still gets its repr' => sub {
    my ($graphs, $mop) = load(<<'SRC', 'inherited_reader');
use experimental 'class';
class Base  { field $v :param :reader = 5; }
class Child :isa(Base) { method own { return 3 } }
my $c = Child->new(v => 9);
print $c->v + $c->own, "\n";
SRC

    my %call;
    for my $g (values %$graphs) {
        for my $n ($g->nodes->@*) {
            next unless blessed($n) && $n->operation eq 'Call';
            next unless ($n->dispatch_kind // '') eq 'method';
            $call{ $n->name // '?' } = $n;
        }
    }

    ok $call{v}, 'found the inherited reader call' or return;
    is $call{v}->target, undef,
        'a synthesized reader has no metaobject to target';
    is $call{v}->stamp, 'Int',
        'and is stamped anyway, from the field type on the DECLARING class';
};

# The wire-vs-graph disagreement die (Analysis.pm) is load-bearing: the producer
# and this loader each derive a method's return type independently, and where
# both commit and disagree one of them is wrong. Moving the wire's value onto
# MOP::Method::return_type re-sources the die's LEFT operand; if the RIGHT is
# not still derived from the graph, the die degrades into comparing a value
# against itself and never fires again -- silently.
subtest 'the wire/graph disagreement still dies' => sub {
    my $file = "$dir/disagree.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nuse experimental 'class';\n"
        . "class Base { method m { return 7 } }\n"
        . "my \$b = Base->new; print \$b->m, \"\\n\";\n";
    close $fh;
    my $json = qx{$PERL -I$SON -MO=SoN,json,package=main $file 2>$dir/disagree.err};
    ok length $json, 'producer emitted JSON' or return;

    # Lie on the wire: the graph plainly returns an Int constant.
    my $data = JSON::PP->new->decode($json);
    is $data->{classes}{Base}{method_return_types}{m}, 'Int',
        'the wire and the graph agree to begin with' or return;
    $data->{classes}{Base}{method_return_types}{m} = 'Str';

    my $err;
    try { Chalk::IR::Serialize::JSON::from_json(JSON::PP->new->encode($data)) }
    catch ($e) { $err = $e }

    ok defined $err, 'the loader refused' or return;
    like $err, qr/return type 'Str' on the wire but 'Int' derived from its graph/,
        'and said which two disagreed';
};

done_testing;
