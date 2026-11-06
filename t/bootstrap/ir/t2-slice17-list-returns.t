# ABOUTME: T2 slice 17 -- a sub returning a list returns it in the caller's context: the list
# ABOUTME: (flattened) where it wants one, perl's scalar where it wants one (last, a count, undef).
our $LAST_LL;
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

sub through_llvm ($src, $env) {
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
    $LAST_LL = $units->[0]{ll};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    local @ENV{ keys %$env } = values %$env;
    my $out = qx(timeout 20 $LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return ($out, $pl);
}

sub perl_says ($pl, $env) {
    local @ENV{ keys %$env } = values %$env;
    return scalar qx($^X $pl 2>/dev/null);
}

sub write_pl ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    return $pl;
}
for my $case (
    [ q{sub two { return (1, 2) } my @l = two(); my $s = two(); print scalar(@l), " $l[1] $s\n";}, 'return (1, 2): a list, or its last' ],
    [ q{sub all { my @c = (4, 5, 6); return @c } my @l = all(); my $n = all(); print "@l $n\n";}, 'return @c: a list, or its count' ],
    [ q{sub none { return } my @l = none(); my $s = none(); print scalar(@l), defined $s ? "d" : "u", "\n";}, 'a bare return: empty, or undef' ],
    [ q{sub g { return (7, 8) } sub f { return g() } my @x = f(); print "@x\n";}, 'returned through another sub' ],
    [ q{sub f { my $n = shift; return ($n, $n * 2) } print f(4), "\n";}, 'printed: its elements' ],
    [ q{sub g { () } my $d = () = g(); my @e = (1, g(), 2); print "$d ", scalar(@e), "\n";}, 'an empty list returned is no element (pvm 104)' ],
    [ q{sub f { my ($c) = @_; if ($c) { return } "v" } my @l = f(1); my @m = f(0); print scalar(@l), scalar(@m), "\n";}, 'a bare return merged with a last value' ],
    [ q{sub items { my $r = shift; return $r->@* } my @got = items([1, 2, 3]); my $count = items([4, 5]); print scalar(@got), " ", $count, "\n";}, 'a scalar call printed is a scalar (count, not elements)' ],
    [ q{sub f { return } sub g { return (1, 2) } my @a = (0); push @a, f(); push @a, g(); print scalar(@a), "\n";}, 'push of a call returning a list' ],
) {
    my ($src, $name) = @$case;
    $LAST_LL = '';
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
    like($LAST_LL, qr/^; chalk T2/m, "$name: lowered through T2");
}

# @_ HANDED TO A LIST may be written through: perl's answer, or refused.
{
    my $src = q{sub pair { return ("a", @_) } my @p = pair(1, 2); print "@p\n";};
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (defined $got) { is($got, perl_says($pl, {}), "\@_ in a returned list: perl's answer") }
    else { like($@, qr/GAP|refused at run time|^lower: /, "\@_ in a returned list: refused by name") }
}

done_testing;
