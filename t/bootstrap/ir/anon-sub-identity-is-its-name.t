# ABOUTME: An AnonSub reaching the wire keeps its name, and its name IS its identity.
# ABOUTME: A reloaded AnonSub must hash identically to the graph that produced it.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed);
use lib 'lib';

use Chalk::IR::Serialize::JSON;

# An AnonSub node reaches the wire whenever the sub is a VALUE rather than an
# immediate callee -- assigned to a hash/array element, or passed as a call
# argument. It is elided only when a Call absorbs it:
#
#   $SIG{__WARN__} = sub { 1; };   Assign(Subscript, AnonSub)   node survives
#   apply(sub { 7 })               Call(AnonSub)                node survives
#   sub { 7 }->()                  Call names the body          node elided
#
# IDENTITY IS THE SITE. A non-capturing anon sub has one CV per site, not one
# per evaluation -- measured against perl 5.42.0:
#
#   map { sub { 7 } } (1,2,3)          1 distinct CV
#   for (1..3) { push @r, sub {7} }    1 distinct CV
#   sub mk { sub {7} } (mk(), mk())    SHARED, across CALL FRAMES
#
# so `<enclosing>::__ANON__:<line>:<targ>` names exactly the thing perl treats
# as one CV. Two AnonSubs with the same name ARE the same sub, and merging
# them is what perl itself does.
#
# WHAT THIS REPLACES: anon_id, a PROCESS-GLOBAL CONSTRUCTION-ORDER COUNTER
# baked into content_hash and never serialized. Three defects, all closed by
# keying on the name instead:
#
#   1. A reloaded AnonSub got a different anon_id than the one written, so its
#      content_hash differed from the graph that produced it. Silent.
#   2. anon_id depended on how many AnonSubs were built earlier IN THE PROCESS,
#      so it varied with load order across documents -- a determinism hazard
#      against the byte-identical-codegen requirement.
#   3. Uniqueness came from counting rather than from anything about the sub.
#
# anon_id defeated dedup to prevent a merge that would be wrong under a
# body-only hash (two capturing subs with identical bodies are different
# values). The name makes the merge RIGHT precisely when it should happen,
# because the name encodes the site and the site is the identity.

my $FIXTURE = 't/bootstrap/ir/data/anon-sub-as-value.json';

my $wire = do {
    open my $fh, '<', $FIXTURE or plan skip_all => "fixture missing: $!";
    local $/; <$fh>;
};

sub anon_nodes {
    my ($graphs) = @_;
    my @out;
    for my $k (sort keys $graphs->%*) {
        my $g = $graphs->{$k};
        next unless blessed($g) && $g->can('nodes');
        push @out, grep {
            blessed($_) && $_->can('operation') && $_->operation eq 'AnonSub'
        } $g->nodes->@*;
    }
    return @out;
}

my $graphs = Chalk::IR::Serialize::JSON::from_json($wire);
my @anon   = anon_nodes($graphs);

subtest 'an AnonSub crossing the wire keeps its name' => sub {
    is(scalar(@anon), 2, 'the fixture carries two AnonSub nodes')
        or diag 'fixture: $SIG{__WARN__} = sub {...}; apply(sub {...})';

    my @names = sort map { $_->can('name') ? ($_->name // '<undef>') : '<NO FIELD>' } @anon;

    is_deeply(\@names, [
        'main::__PROGRAM__::__ANON__:2:2',
        'main::__PROGRAM__::__ANON__:3:6',
    ], 'both names survive the loader');

    # Each named body must actually exist as a methods entry. A name pointing
    # at nothing is the dangling-body class one step removed -- the reference
    # survives and the referent does not.
    for my $n (@anon) {
        next unless $n->can('name') && defined $n->name;
        ok(exists $graphs->{ $n->name }, $n->name . ' has a body in methods');
    }
};

subtest 'identity is the name, not a construction counter' => sub {
    for my $n (@anon) {
        like($n->content_hash, qr/\Q__ANON__\E/,
            'content_hash names the site');
        unlike($n->content_hash, qr/anon_id/,
            'content_hash does NOT carry a construction counter');
    }

    # THE LOAD-BEARING ASSERTION: reloading the SAME wire must produce the
    # SAME hashes. Under anon_id it could not -- the counter is process-global
    # and keeps climbing, so a second load in one process hashed differently
    # from the first. That is the identity instability, and it is invisible
    # to any test that loads a document only once.
    my @first  = sort map { $_->content_hash } @anon;
    my @second = sort map { $_->content_hash }
                 anon_nodes(Chalk::IR::Serialize::JSON::from_json($wire));

    is_deeply(\@second, \@first,
        'a second load of the same wire yields the same content hashes');

    # And two DIFFERENT sites must not collide, or the merge the name enables
    # would fuse two distinct subs.
    my %seen; $seen{$_}++ for @first;
    is(scalar(keys %seen), 2, 'the two sites hash differently');
};

done_testing;
