# ABOUTME: hydrate() reproduces the wire; infer() types it. Two jobs, two subs,
# ABOUTME: and inference never touches the raw records the MOP was built from.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';
use JSON::PP;
use File::Temp qw(tempfile);
use Chalk::IR::Analysis ();
use Chalk::IR::Serialize::JSON ();
use Scalar::Util qw(blessed);

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "perl 5.42 not found"         unless -x $PERL;

# Phase 5 step 4. Analysis::run did TWO jobs in one pass: it BUILT the MOP by
# replaying the wire's raw `classes` records, and it INFERRED types over the
# graphs. Those are different jobs and only one is T1's -- construction is
# deserialization (the loader's), inference is T1's.
#
# perigrin, 2026-08-31: hydration and inference are ORDERED, not interleaved.
# Hydration completes; inference then reads the finished model repeatedly. That
# is what makes the cut possible at all.

my $prog = <<'PROG';
use 5.42.0;
use feature 'class';
no warnings 'experimental::class';
class Counter {
    field $n :param = 0;
    method val { return $n }
}
say(Counter->new(n => 7)->val);
PROG

my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
print $fh $prog;
close $fh;
my $json = qx($PERL -I$SON -MO=SoN,json,package=main,package=Counter $tmp 2>/dev/null);
plan skip_all => "B::SoN produced no JSON" unless $json =~ /\S/;

sub decoded () {
    my $data = JSON::PP->new->decode($json);
    my %graphs;
    for my $name (sort keys $data->{methods}->%*) {
        $graphs{$name} = Chalk::IR::Serialize::JSON::_deserialize_graph(
            $data->{methods}{$name});
    }
    return (\%graphs, $data->{classes});
}

subtest 'hydrate builds the MOP and attaches it, without inferring' => sub {
    my ($graphs, $classes) = decoded();
    Chalk::IR::Analysis->hydrate($graphs, $classes);

    my ($any) = values $graphs->%*;
    ok(defined $any->mop, 'every graph carries the MOP edge after hydrate');
    ok($any->mop->is_sealed, 'and the MOP is sealed');
    ok(scalar(keys $any->mop->graphs->%*), 'the graph registry is populated');
};

subtest 'infer needs NO raw records -- only graphs and the MOP edge' => sub {
    my ($graphs, $classes) = decoded();
    Chalk::IR::Analysis->hydrate($graphs, $classes);

    # THE POINT OF THE SPLIT: infer's signature has no $classes slot. If it
    # still needed the wire section this call could not be written.
    my $out = Chalk::IR::Analysis->infer($graphs);
    ok(defined $out, 'infer returns the graph set');

    my $typed = 0;
    for my $g (values $out->%*) {
        for my $n ($g->nodes->@*) {
            next unless blessed($n) && $n->isa('Chalk::IR::Value');
            $typed++ if defined $n->stamp;
        }
    }
    ok($typed > 0, "infer typed $typed Value nodes with no raw records");
};

subtest 'run is exactly hydrate-then-infer' => sub {
    my ($g1, $c1) = decoded();
    Chalk::IR::Analysis->hydrate($g1, $c1);
    Chalk::IR::Analysis->infer($g1);

    my ($g2, $c2) = decoded();
    Chalk::IR::Analysis->run($g2, $c2);

    my $sig = sub ($set) {
        join '|', map { my $g = $set->{$_};
            "$_=" . join(',', map { ($_->id // '?') . ':' . ($_->stamp // '-') }
                grep { blessed($_) && $_->isa('Chalk::IR::Value') } $g->nodes->@*)
        } sort keys $set->%*;
    };
    is($sig->($g1), $sig->($g2),
       'composing the halves gives byte-identical stamps to run()');
};

done_testing;
