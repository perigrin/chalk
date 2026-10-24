# ABOUTME: substr as a value: offset from either end, length to the end, past it, or
# ABOUTME: short of it -- B::SoN -> chalk -> lli == perl; outside the string, refused at run time.
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

# SUBSTR AS A VALUE (pvm string-ops cases refused "builtin substr"). A copy
# of the bytes, with perl's offset and length rules. Outside the string perl
# answers undef with a warning; that is refused at run time (exit 255).
for my $case (
    [ q{my $s = $ENV{S} // "Hello world"; print join("|", substr($s, 6), substr($s, 3, 2), substr($s, -5, 3), substr($s, 2, -3), substr($s, 0, 100), substr($s, 11), substr($s, 3, -20), substr($s, -3)), "\n";}, "world|lo|wor|llo wo|Hello world||" . "|rld\n", 'the rules' ],
    [ q{my $s = $ENV{S} // "12345"; my $n = substr($s, 1, 2) + 1; print "$n\n";}, "24\n", 'a number read from a substring stops at its end' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

my $err = do { local $@; eval { through_llvm(q{my $s = $ENV{S} // "abc"; print substr($s, 5), "\n";}) }; $@ };
like($err, qr/lli exited 255/, 'outside the string is refused at run time');

done_testing;
