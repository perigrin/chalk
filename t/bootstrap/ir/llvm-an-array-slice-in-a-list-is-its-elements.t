# ABOUTME: An array slice in a list is a copy of each element it names, in order -- from
# ABOUTME: the end when negative, undef past it -- and one perl would alias is refused.
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

# AN ARRAY SLICE IN A LIST is the elements its indices name. It was refused
# ("a list with a List in it", pvm 159 213).
for my $c (
    [ q{my @a = (5, 6, 7, 8); my @b = @a[1 .. 2]; print "@b\n";},                 "6 7\n",   'a slice by a range' ],
    [ q{my @a = (5, 6, 7, 8); my @i = (3, 0); my @b = @a[@i]; print "@b\n";},       "8 5\n",   'a slice by an array of indices' ],
    [ q{my @a = (5, 6, 7, 8); my @b = @a[-1, 9]; print scalar(@b), " $b[0]\n";},    "2 8\n",   'from the end; past it is undef' ],
    [ q{my @a = (5, 6, 7); my $s = ""; for my $x (@a[1 .. $#a]) { $s .= $x } print "$s\n";}, "67\n", 'a loop over a slice reads its elements' ],
) {
    my ($src, $want, $name) = @$c;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

# A SLICE PERL WOULD ALIAS is refused: B::SoN walks a copy, so a store
# through the loop variable would not reach the array (pvm 192).
{
    eval { through_llvm(q{sub g { $_[0] = 5 } my @n = (1, 2); g($_) for @n[1 .. 1]; print "@n\n";}) };
    like($@, qr/GAP: a loop over an array slice whose element is passed or referenced/, 'an aliased slice element is refused');
}

done_testing;
