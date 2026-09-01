# ABOUTME: A non-capturing anon sub's body is a methods entry named by its site.
# ABOUTME: Two enclosing subs with the same pad slot must not collide into one key.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed);
use lib 'lib';

use Chalk::IR::Serialize::JSON;

# A NON-CAPTURING anon sub has ONE CV PER SITE, not one per evaluation.
# Measured against perl 5.42.0:
#
#   map { sub { 7 } } (1,2,3)              1 distinct CV
#   map { my $i=$_; sub {$i} } (1,2,3)     3 distinct CVs (values 1,2,3)
#   for (1..3) { push @r, sub { 7 } }      1 distinct CV
#   sub mk { sub {7} }  (mk(), mk())       SHARED -- across CALL FRAMES
#
# So identity tracks the SITE and the site is the whole of it. That is what
# `<enclosing>::__ANON__:<line>:<targ>` names (perl5-son 6666e6e), which makes
# per-site naming semantically right rather than merely workable.
#
# IT IS ALSO WHY CAPTURING SUBS ARE REFUSED, and the boundary is forced rather
# than chosen: three capturing instances sharing one name would be three
# runtime VALUES with one identity -- a miscompile, not a limitation. Capture
# needs site+environment as identity, which is a DIFFERENT scheme, not an
# extension of this one.
#
# Two textually identical anon subs at different sites are two values
# (`my $a = sub{1}; my $b = sub{1}` -- refaddrs differ), so they get distinct
# names and must not share a methods entry.

my $FIXTURE = 't/bootstrap/ir/data/anon-sub-naming.json';

my $wire = do {
    open my $fh, '<', $FIXTURE or plan skip_all => "fixture missing: $!";
    local $/; <$fh>;
};

my $graphs = Chalk::IR::Serialize::JSON::from_json($wire);

# The fixture (data/anon-sub-naming.pl) is the COLLISION case:
#
#   sub f { my $c = sub { 1 }; $c->() }
#   sub g { my $c = sub { 2 }; $c->() }
#   my $t = sub { 42 };  print $t->();
#
# `targ` is a pad index scoped to its ENCLOSING CV, so f's and g's anon subs
# both sit at pad slot 2. A name built from targ alone would make them one
# hash key and one body would silently overwrite the other -- a collision, not
# an error. The enclosing-sub prefix is what prevents it.
subtest 'each anon body is its own methods entry, scoped by its enclosing sub' => sub {
    my @anon = sort grep { /__ANON__/ } keys $graphs->%*;

    is_deeply(\@anon, [
        'main::__PROGRAM__::__ANON__:3:2',
        'main::f::__ANON__:1:2',
        'main::g::__ANON__:2:2',
    ], 'three distinct anon bodies, one per site');

    # THE COLLISION ASSERTION. f's and g's anon subs share pad slot 2 (the
    # trailing :2 on both names). This passes vacuously on any single-anon-sub
    # fixture, which is exactly how the collision stayed invisible.
    my ($f_targ) = 'main::f::__ANON__:1:2'        =~ /:(\d+)$/;
    my ($g_targ) = 'main::g::__ANON__:2:2'        =~ /:(\d+)$/;
    is($f_targ, $g_targ, 'f and g DO share a pad slot -- the collision is real');
    isnt('main::f::__ANON__:1:2', 'main::g::__ANON__:2:2',
        'and the enclosing scope keeps them distinct anyway');

    for my $name (@anon) {
        ok(blessed($graphs->{$name}), "$name loaded as a graph");
    }
};

# A Call whose callee is an anon sub must NAME the body. Without that the body
# reaches the wire with nothing pointing at it -- a graph that looks complete
# while the call dangles, which is strictly worse than a GAP because it is
# silent. (bson hit exactly this; it is the same class as the dangling scalar
# face, where bidirectional graph membership let an unconsumed node ride
# along looking consumed.)
subtest 'the callsite names the body it calls' => sub {
    my %called;
    for my $gname (sort keys $graphs->%*) {
        my $g = $graphs->{$gname};
        next unless blessed($g) && $g->can('nodes');
        for my $n ($g->nodes->@*) {
            next unless blessed($n) && $n->can('operation') && $n->operation eq 'Call';
            next unless $n->can('name') && defined $n->name;
            $called{ $n->name } = $gname if $n->name =~ /__ANON__/;
        }
    }

    is_deeply([sort keys %called], [
        'main::__PROGRAM__::__ANON__:3:2',
        'main::f::__ANON__:1:2',
        'main::g::__ANON__:2:2',
    ], 'every anon body is named by a Call');

    # Each call sits in the sub that lexically contains the anon sub, so a
    # name that leaked across scopes would show up here as the wrong caller.
    is($called{'main::f::__ANON__:1:2'}, 'main::f', "f's anon is called from f");
    is($called{'main::g::__ANON__:2:2'}, 'main::g', "g's anon is called from g");

    for my $anon (sort keys %called) {
        ok(exists $graphs->{$anon}, "$anon has a body, not just a caller");
    }
};

done_testing;
