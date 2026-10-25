# ABOUTME: A hash literal holds what it was given -- a copy of a hash spread in it, an undef,
# ABOUTME: a missed element, a value read by its tag: B::SoN -> chalk -> lli == perl.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;

require Chalk::CodeGen::Pipeline;

# The whole program through B::SoN, chalk's pipeline and lli; its stdout.
sub through_llvm ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    die "load: $err\n" if $err;
    die "lower: $units->[0]{err}\n" unless $units->[0]{ok};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    my $out = qx($LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return $out;
}

# `{ %a }` was counted as pairs (half a pair, and a crash); an undef value,
# or one read by its tag (`{ v => $_[1] }` in a constructor), was refused
# as having "no i64 payload encoding" -- a %HashEntry holds a Slot's fields.
for my $case (
    [ q{my %a = (n => 1); my $h = { %a }; $h->{n} = 5; print "$a{n} $h->{n}\n";}, "1 5\n", 'a hash spread in it is a copy' ],
    [ q{my @x = (1); my $u; my $h = { a => $x[5], b => $u, c => 2 }; print defined $h->{a} ? "d" : "u", defined $h->{b} ? "d" : "u", $h->{c}, "\n";}, "uu2\n", 'an undef and a missed element' ],
    [ q{sub mk { return { v => $_[0] } } my $h = mk("x"); my $g = mk("y"); print "$h->{v}$g->{v}\n";}, "xy\n", 'an argument' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
