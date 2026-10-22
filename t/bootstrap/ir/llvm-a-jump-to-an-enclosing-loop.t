# ABOUTME: A jump to an enclosing loop (`next OUTER`, `last OUTER`) runs as perl does
# ABOUTME: or is refused by name -- never lowered as the inner loop's own next or last.
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

# `next OUTER` WAS LOWERED AS THE INNER LOOP'S `next`: B::SoN routes it to the
# outer loop's continue point -- a Region past the inner loop's exit -- and
# chalk placed that Region inside the inner body, printing `acacac` for perl's
# `aaa` (pvm corpus jumps.md). Until a jump into an enclosing loop's latch is
# lowered, it is refused; a right answer passes too.
for my $case (
    [ q{my @l = ("a","b","c"); OUTER: foreach my $x (@l) { foreach my $y (@l) { next OUTER if $y eq "b"; print $y } } print "\n";},
      "aaa\n", 'next OUTER with nothing after the inner loop' ],
    [ q{my @l = ("a","b","c"); OUTER: foreach my $x (@l) { foreach my $y (@l) { next OUTER if $y eq "b"; print $y } print "|" } print "\n";},
      "aaa\n", 'next OUTER skipping what follows the inner loop' ],
    [ q{my @l = ("a","b","c"); OUTER: foreach my $x (@l) { foreach my $y (@l) { last OUTER if $y eq "b"; print $y } print "|" } print "\n";},
      "a\n", 'last OUTER' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    if (defined $got) { is($got, $want, "$name: perl's answer") }
    else { like($@, qr/^lower: .*enclosing loop/, "$name: refused, naming the jump") or diag $@ }
}

# A PLAIN `next` OR `last` still lowers: it stays inside its own loop.
for my $case (
    [ q{my @l = ("a","b","c"); foreach my $x (@l) { foreach my $y (@l) { next if $y eq "b"; print $y } } print "\n";}, "acacac\n", 'an inner next' ],
    [ q{my @l = ("a","b","c"); foreach my $x (@l) { foreach my $y (@l) { last if $y eq "b"; print $y } } print "\n";}, "aaa\n", 'an inner last' ],
) {
    my ($src, $want, $name) = @$case;
    is(eval { through_llvm($src) } // "died: $@", $want, $name);
}

done_testing;
