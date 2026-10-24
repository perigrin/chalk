# ABOUTME: @ARGV is the program's arguments, from main's argv: through B::SoN ->
# ABOUTME: chalk -> lli, with and without arguments, == perl.
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
# The whole program through B::SoN, chalk's pipeline and lli, run with
# @args; its stdout.
sub through_llvm ($src, @args) {
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
    my $out = qx($LLI $ll @args 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return $out;
}

# @ARGV WAS NOT LOWERED ("EntryDef repr=Array", 13 pvm corpus cases, most
# `$ARGV[0] // 12` -- an input the compiler cannot fold). It is an %Array of
# argv[1..], built once in main's entry and shared by every read, so a shift
# from it is seen after.
for my $case (
    [ q{my $a = $ARGV[0] // 12; print $a + 1, "\n";}, "13\n", "6\n", 'an element, defaulted' ],
    [ q{print scalar(@ARGV), "\n";}, "0\n", "2\n", 'its count' ],
    [ q{my $x = shift(@ARGV) // "d"; print "$x|@ARGV\n";}, "d|\n", "5|b\n", 'a shift, and what is left' ],
    [ q{print "[@ARGV]\n";}, "[]\n", "[5 b]\n", 'interpolated' ],
) {
    my ($src, $none, $two, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $none, "$name, no arguments: perl's answer") or diag $@;
    $got = eval { through_llvm($src, 5, 'b') };
    is($got, $two, "$name, two arguments: perl's answer") or diag $@;
}

# A SHIFT OF AN EMPTY ARRAY IS UNDEF. Stamped Int, it gave the payload 0,
# defined: `shift(@a) // 7` printed 0 for 7, and defined() said yes
# (pre-existing at e1a15d3a). 0 is undef's reading only as a number.
for my $case (
    [ q{my @a = (1); shift @a; my $x = shift(@a) // 7; print "$x\n";}, "7\n", 'an empty Int array, defaulted' ],
    [ q{my @a = (1); my $y = shift @a; my $x = shift @a; print defined($x) ? "d" : "u", "$y\n";}, "u1\n", 'an empty Int array, tested' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    ok(defined $got ? $got eq $want : $@ =~ /^(?:load|lower): /,
        "$name: refused, or perl's answer")
        or diag defined $got ? "got: $got" : $@;
}
{
    my $got = eval { through_llvm(q{my @a = (4, 5); my $x = shift @a; print $x + 1, "\n";}) };
    is($got, "5\n", 'an Int shift read as a number: perl\'s answer') or diag $@;
}

done_testing;
