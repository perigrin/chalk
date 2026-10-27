# ABOUTME: unary minus on numbers (a string operand stops), and a float zero with its sign
# ABOUTME: bit set prints as perl prints it, "0": B::SoN -> chalk -> lli == perl.
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

# A float zero with its sign set printed "-0" (%.15g); perl prints "0"
# (older). Unary minus was not lowered (pvm 038).
for my $c (
    [ q{my $a = -1.5; my $z = $a * 0; print "$z\n";} ],
    [ q{my $a = $ARGV[0] // 12; my $f = 2.5; my $i = 7; print -$a, " ", -$f, " ", -$i, " ", -(0.5 - 0.5), "\n";} ],
    [ q{my $x = 3; my $y = -$x * 2; print $y, " ", - -$x, "\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# ON A STRING perl negates the text (-"abc" is "-abc"): refused or stopped.
for my $src (q{my $s = $ENV{NOPE} // "abc"; print -$s, "\n";}) {
    my $got = eval { through_llvm($src) };
    if (defined $got) { is($got, qx($^X -e '$src'), "perl's answer: $src") }
    else { like($@, qr/GAP:|LLVM backend:|lli exited 255/, "refused or stopped: $src") }
}

done_testing;
