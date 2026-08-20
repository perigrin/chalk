# ABOUTME: A resolved direct Call carries its callee METAOBJECT, not a bare graph.
# ABOUTME: target is the MOP handle; resolved_graph was the flat-graph fallback.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
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
    return Chalk::IR::Serialize::JSON::from_json($json);
}

# Find the direct Call to $callee in the entry graph.
sub direct_call ($graphs, $callee) {
    my $g = $graphs->{'main::__PROGRAM__'} // $graphs->{'main::__main__'}
        or return undef;
    for my $n (@{ $g->nodes }) {
        next unless $n->operation eq 'Call';
        next unless ($n->can('dispatch_kind') ? $n->dispatch_kind // '' : '') eq 'direct';
        return $n if ($n->name // '') eq $callee;
    }
    return undef;
}

# `target` is the field Call.pm documents as "a MOP::Method/Sub handle ... so
# codegen can read the callee's graph/params/return-type directly without going
# through the symbol table at emit time". Before this step it was populated
# ONLY by the self-hosted parser, and the B::SoN path used resolved_graph -- a
# bare Chalk::IR::Graph -- because a top-level sub had no metaobject to name.
# 1a/1b gave it one.
subtest 'a direct call to a file-level sub carries its MOP::Sub' => sub {
    my ($graphs) = load('sub f { 42 } print f(), "\n";', 'plain');
    my $call = direct_call($graphs, 'main::f');
    ok defined $call, 'found the direct Call node' or return;

    my $t = $call->can('target') ? $call->target : undef;
    ok defined $t, 'the Call carries a target' or return;
    isa_ok $t, 'Chalk::MOP::Sub';
    is $t->name, 'f', 'it is the callee metaobject';
    ok defined $t->graph, 'and the graph is reachable THROUGH it';
};

# The point of the metaobject: sub-level facts come from the MOP rather than
# from scanning. uses_args is the one that cannot be recovered reliably -- `@_`
# has three IR spellings and vanishes entirely for `my ($a,$b) = @_`.
subtest 'callee metadata is reachable from the call site' => sub {
    my ($graphs) = load('sub f { my $n = shift; $n+1 } print f(1), "\n";', 'meta');
    my $call = direct_call($graphs, 'main::f');
    ok defined $call, 'found the Call' or return;
    my $t = $call->can('target') ? $call->target : undef;
    ok defined $t, 'target present' or return;
    ok $t->uses_args, 'uses_args is readable at the CALL SITE, unscanned';
};

# The graph must still be reachable, because that is what the backend lowers
# today. Going through the metaobject is the change; losing the graph is not.
subtest 'the callee graph is the same object either way' => sub {
    my ($graphs) = load('sub f { 42 } print f(), "\n";', 'same');
    my $call = direct_call($graphs, 'main::f');
    ok defined $call, 'found the Call' or return;
    my $t = $call->can('target') ? $call->target : undef;
    ok defined $t, 'target present' or return;
    is $t->graph, $graphs->{'main::f'},
        'target->graph IS the loaded callee graph, not a copy';
};

# THE SCOPE FENCE. `resolved_graph` is not deleted, and this pins WHY rather
# than leaving it to look like unfinished work.
#
# The loader's repr fixpoint (_resolve_direct_calls / _seed_direct_call_arg_reprs)
# runs BEFORE _replay_classes seals the MOP, so during those passes no
# metaobject exists to point at. The field is loader-internal working state for
# that window. Retiring it is a loader-ORDERING change, not a call-lowering one.
#
# What this guards: no consumer OUTSIDE the loader may read it. The backend
# reads `target`.
subtest 'resolved_graph is loader-internal only' => sub {
    my @offenders;
    for my $root (qw(lib)) {
        my @files = split /\n/, qx{find $root -name '*.pm'};
        # A 0-file scan is indistinguishable from a clean one, so the fence
        # would PASS from any cwd where lib/ does not exist -- verified: run
        # from /tmp it reported "nothing consumes resolved_graph" having read
        # nothing at all. Assert the scan happened before trusting its result.
        cmp_ok scalar @files, '>', 100,
            "the scan actually read lib/*.pm (found ${\ scalar @files })"
            or return;
        for my $f (@files) {
            next if $f =~ m{IR/Serialize/JSON\.pm$};   # the loader itself
            next if $f =~ m{IR/Node/Call\.pm$};        # the declaration
            open my $fh, '<', $f or next;
            my $src = do { local $/; <$fh> };
            close $fh;
            # strip comments so the prose above does not self-trip
            $src =~ s/^\s*#.*$//mg;
            push @offenders, $f if $src =~ /resolved_graph/;
        }
    }
    is_deeply \@offenders, [],
        'nothing outside the loader consumes resolved_graph'
        or diag "offenders: @offenders";
};

# A CALLEE WITH A GRAPH BUT NO METAOBJECT is a disagreement between the two
# halves of the wire, and it is reachable: the producer writes the graph
# UNCONDITIONALLY and only then calls _record_sub, which returns early for a
# `method` CV and for a `:reader` accessor. Measured -- `Widget::go($w)` on a
# class method gives resolved_graph=SET, target=UNDEF.
#
# The backend now resolves THROUGH the metaobject, so without this the failure
# surfaced there as "an unknown or builtin sub" -- actively wrong, since the sub
# is neither. The loader has both facts in hand and says what is really true.
subtest 'a graph without a metaobject is a loud disagreement' => sub {
    my $src = <<'PERL';
use feature 'class';
no warnings 'experimental::class';
class Widget { field $n :param = 0; method go { 9 } }
my $w = Widget->new(n => 5);
print Widget::go($w), "\n";
PERL
    my $file = "$dir/mcall.pl";
    open my $fh, '>', $file or die $!;
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    # No package filter: the class must be emitted for its graph to exist.
    my $json = qx{$PERL -I$SON -MO=SoN,json $file 2>$dir/mcall.err};
    ok length $json, 'producer emitted JSON' or return;

    my $err = '';
    eval { Chalk::IR::Serialize::JSON::from_json($json); 1 } or $err = $@ // '';
    like $err, qr/^GAP:/, 'refuses loudly rather than mislabelling the callee';
    like $err, qr/graph set and its class sub records disagree/,
        'and names the real cause'
        or diag $err;
};

done_testing;
