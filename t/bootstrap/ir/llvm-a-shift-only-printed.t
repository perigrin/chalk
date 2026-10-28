# ABOUTME: shift/pop of an Int array whose value is only coerced (printed,
# ABOUTME: concatenated) is read as its Slot: an empty array's undef prints "".
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


# Refused: an empty array gives undef, which an Int reads as 0 (pvm 018).
for my $src (
    q{my @a = (10, 20, 30); my $x = shift @a; print $x, "\n"; print scalar(@a), "\n";},
    q{my @a = (1); my $x = shift @a; my $y = shift @a; print "[$x][", $y // "u", "]\n";},
    q{my @a = (4, 5); my $p = pop @a; print "p=$p ", scalar(@a), "\n";},
) {
    my $want = qx($^X -e '$src' 2>/dev/null);
    my $got = eval { through_llvm($src) };
    my $err = $@;
    ok(defined $got ? $got eq $want : $err =~ /GAP/, "perl's answer or refused: $src")
        or diag "got: ", $got // $err;
    is($got, $want, "perl's answer: $src") if $src =~ /10, 20/;
}

done_testing;
