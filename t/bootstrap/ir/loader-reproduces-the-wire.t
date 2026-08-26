# ABOUTME: The loader's whole job is reproducing the graph the frontend sent.
# ABOUTME: Decode then re-encode: any difference is the loader doing something else.

use 5.42.0;
use utf8;
use Test2::V0;
use JSON::PP ();   # no import: its to_json/from_json collide with Chalk's
use File::Temp;

use Chalk::IR::Serialize::JSON qw(to_json from_json);

# THE LOADER'S CONTRACT, stated as a test rather than a comment:
#
#   > The Loader's job is to reproduce the graph that the Frontend serialized
#   > ... that's it.
#
# Round-tripping IS that definition, not a proxy for it. Decode the wire,
# re-encode the result, compare. A difference means the loader did something
# other than reproduce -- and today it does: it runs 17 inference passes
# (Chalk::IR::Analysis, invoked from from_json at Serialize/JSON.pm:900), so
# the re-encoded graph carries stamps the wire never sent.
#
# NOTE THE DIRECTION. t/bootstrap/ir-node-unify-roundtrip.t already tests
# graph -> JSON -> graph, which is the SERIALIZER's property (lossless
# inverse). This tests JSON -> graph -> JSON, which is the LOADER's. Only the
# second can see inference, because inference adds facts the wire did not have.
#
# WHAT THIS TEST IS FOR. It was written to measure the gap that slice 4's first
# delivery closes -- splitting T1 out of the loader. Running it found something
# else first, and the something else has to be fixed before this test can
# measure what it was built for.
#
# MEASURED 2026-08-26, and it is the OPPOSITE of what was predicted. The loader
# was expected to ADD stamps (inference the wire did not send). Every observed
# difference is the reverse: `wire=Int reloaded=(none)`. Stamps are DROPPED.
#
# The cause is not the loader. **`to_json` never emits a `stamp` field** --
# verified, the string appears in that whole function's range exactly once, in
# an error message. Chalk's serializer cannot express the type axis at all.
# A comment elsewhere in the module states this in passing without drawing the
# conclusion: "Chalk's own serializer emits no stamp, so this only fires for
# B::SoN-produced JSON."
#
# That matters beyond this test: `to_json` is the SELF-HOSTING output path. A
# serializer that drops types means chalk cannot hand a typed graph to
# anything, including a future chalk.
#
# So the order is: teach `to_json` to emit stamps, THEN this test can see the
# T1 split (which will show as stamps ADDED by the loader), and only then does
# it become an assertion. See docs/plans/2026-08-24-loader-analysis-pipeline.md.

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = "$ENV{HOME}/dev/perl5-son/lib";

sub wire_for ($src) {
    my ($fh, $tmp) = File::Temp::tempfile(SUFFIX => '.pl', UNLINK => 1);
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $json = qx{$PERL -I$SON -MO=SoN,json,package=main $tmp 2>/dev/null};
    return $json =~ /\S/ ? $json : undef;
}

# Compare node-by-node on the fields the wire actually carries, rather than
# string-comparing the JSON: key order, whitespace and float formatting are
# the serializer's business, not the loader's.
sub stamp_diffs ($before_json, $after_json) {
    my $before = JSON::PP->new->decode($before_json);
    my $after  = JSON::PP->new->decode($after_json);
    my @diffs;

    for my $gname (sort keys %{ $before->{methods} // {} }) {
        my $b = $before->{methods}{$gname}{nodes} // [];
        my $a = ($after->{methods}{$gname} // {})->{nodes} // [];
        unless (@$a) { push @diffs, "$gname: MISSING from re-encode"; next }

        # NOT KEYED ON id. Wire ids are POSITIONAL, and `to_json` renumbers by
        # its own topological walk -- wire id=0 is Start while reloaded id=0 is
        # a Constant. An earlier version of this comparison keyed on id and
        # reported three phantom differences, including two stamps that looked
        # SWAPPED (Int<->ArrayRef) but were simply two different nodes.
        #
        # Compare the multiset of (op, stamp) pairs per graph instead. That is
        # invariant under renumbering and still catches a stamp appearing,
        # vanishing, or changing -- which is all this test is about. It cannot
        # localise WHICH node of a repeated op changed, and does not need to.
        my (%b_count, %a_count);
        $b_count{ ( $_->{op} // '?' ) . "\0" . ( $_->{stamp} // '(none)' ) }++
            for @$b;
        $a_count{ ( $_->{op} // '?' ) . "\0" . ( $_->{stamp} // '(none)' ) }++
            for @$a;

        for my $key (sort keys %b_count) {
            my $delta = ( $b_count{$key} // 0 ) - ( $a_count{$key} // 0 );
            next if $delta <= 0;
            my ($op, $stamp) = split /\0/, $key;
            push @diffs, sprintf('%s %s:%s -- %d fewer after reload',
                $gname, $op, $stamp, $delta);
        }
        for my $key (sort keys %a_count) {
            my $delta = ( $a_count{$key} // 0 ) - ( $b_count{$key} // 0 );
            next if $delta <= 0;
            my ($op, $stamp) = split /\0/, $key;
            push @diffs, sprintf('%s %s:%s -- %d MORE after reload',
                $gname, $op, $stamp, $delta);
        }
    }
    return \@diffs;
}

my %programs = (
    'literal print'  => 'say(42);',
    'array element'  => 'my @a=(1,2,3); say($a[1]);',
    'sub with args'  => 'sub f { my $x = shift; return $x + 1 } say(f(2));',
    'if/else'        => 'my $c=1; my $v; if ($c) { $v=1 } else { $v=2 } say($v);',
);

my $total = 0;
for my $name (sort keys %programs) {
    subtest $name => sub {
        my $wire = wire_for($programs{$name});
        skip_all "producer emitted no JSON for $name" unless $wire;

        my ($graphs) = from_json($wire);
        ok $graphs, 'the wire loads';

        my $reencoded = to_json($graphs);
        ok $reencoded, 'the loaded graph re-encodes';

        my $diffs = stamp_diffs($wire, $reencoded);
        $total += scalar @$diffs;

        # RECORDING, not asserting -- see the header. Each entry is a fact the
        # loader added that the frontend did not send.
        diag(sprintf('%s: %d node(s) changed stamp through the loader',
            $name, scalar @$diffs));
        diag("  $_") for ( $diffs->@* )[ 0 .. ( @$diffs > 5 ? 4 : $#$diffs ) ];
    };
}

diag('');
diag("TOTAL stamp differences across the round trip: $total");
diag('Every one is now a stamp the LOADER ADDED -- Print seeded Boolean,');
diag('Subscript/Call/Add narrowed from Unknown. That is inference running');
diag('inside the loader, and it is the size of the T1 split. When T1 moves');
diag('out, this reaches zero and becomes an assertion.');

done_testing;
