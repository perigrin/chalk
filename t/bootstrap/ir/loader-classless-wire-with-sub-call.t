# ABOUTME: A wire with no `classes` key and a sub call must load -- a SEEDED
# ABOUTME: `main` is not evidence the wire declared anything about it.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';
use JSON::PP;
use File::Temp qw(tempfile);
use Chalk::IR::Serialize::JSON ();

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "perl 5.42 not found"         unless -x $PERL;

# `classes` and `methods` are INDEPENDENT wire keys. The loader is defensive
# over JSON of unknown provenance (perigrin, 2026-08-30: "we're just handed
# JSON"), so a wire carrying subs and no `classes` is a shape it must survive
# -- whatever B::SoN happens to emit today.
#
# The hazard: Chalk::MOP's ADJUST seeds class `main` on EVERY load. So after
# the Phase-2 classes-guard dissolution, `main` is in the MOP whether or not
# the wire ever mentioned it, and _attach_call_targets read that presence as
# "the wire declared this class" -- then found no sub recorded on it and
# reported a contradiction that does not exist.
#
# Found by the G4 review testing a shape the tests did not cover: a class-less
# program WITH a sub call. The existing class-less pin (`my $x = 1 + 2; print`)
# has no call, so it never reached the die.

my $prog = <<'PROG';
use 5.42.0;
package main;
sub f { return 1 }
sub g { return f() }
say(g());
PROG

my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
print $fh $prog;
close $fh;
my $json = qx($PERL -I$SON -MO=SoN,json,package=main $tmp 2>/dev/null);
plan skip_all => "B::SoN produced no JSON" unless $json =~ /\S/;

my $data = JSON::PP->new->decode($json);

subtest 'the producer emits a classes key today' => sub {
    # Recorded so the test states WHY it must synthesise the shape rather than
    # capture one: this defect is not reachable from B::SoN as it stands.
    ok(exists $data->{classes}, 'B::SoN emits `classes` even with no class');
};

subtest 'a wire with NO classes key still loads when it has a sub call' => sub {
    delete $data->{classes};
    my $stripped = JSON::PP->new->canonical->encode($data);

    my $graphs = eval { Chalk::IR::Serialize::JSON::from_json($stripped) };
    my $err = $@;
    ok(!$err, 'from_json does not die')
        or diag("died: $err");
    ok(defined $graphs && keys %$graphs, 'and returns graphs')
        if !$err;
};

done_testing;
