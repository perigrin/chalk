# ABOUTME: an array rebound in an if arm is one array after the if: a push onto it stays:
# ABOUTME: through B::SoN -> chalk -> lli == perl, or refused by name.
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

# `my @l = (1); if ($c) { @l = (5) } push @l, 9; print "@l"` printed "5"
# for perl's "5 9": B::SoN makes @l a TernaryExpr of the two literals, the
# push and the later read both of it, and the read made a fresh array.
for my $case (
    [ q{my $c = $ARGV[0] // 1; my @l = (1); if ($c) { @l = (5) } push @l, 9; print "@l\n";}, "5 9\n", 'rebound in a taken arm' ],
    [ q{my $c = $ARGV[0] // 0; my @l = (1); if ($c) { @l = (5) } push @l, 9; print "@l\n";}, "1 9\n", 'not rebound' ],
    [ q{sub f { my ($c) = @_; my @l = (1); if ($c) { my @x = (5); @l = @x } push @l, 9; return "@l" } print f(1), "|", f(0), "\n";}, "5 9|1 9\n", 'rebound from another array, in a sub' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    if (!defined $got && $@ =~ /GAP/) { pass("$name: refused by name"); diag $@; next }
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
