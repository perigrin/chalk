# ABOUTME: T2 slice 13 -- an array reference is a %Slot (tag 6) over an %Array: [...], \@a,
# ABOUTME: @$r, $r->[i] read and stored, push through it, ref() is ARRAY; one array, two names.
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
    [ q{my $r = [1, 2, 3]; print scalar(@$r), " $r->[1] ", join(",", @$r), " ", ref($r), "\n";}, 'a literal: count, element, join, ref' ],
    [ q{sub cnt { my ($l) = @_; return scalar(@$l) } print cnt([4, 5]), cnt([]), "\n";}, 'passed to a sub' ],
    [ q{my @a = (1, 2); my $r = \@a; push @a, 3; $r->[0] = 9; print "@a ", scalar(@$r), "\n";}, '\@a: one array, two names' ],
    [ q{my $r = [1]; push @$r, 2; my $s = ""; for my $x (@$r) { $s .= $x } print "$s\n";}, 'push through it, a loop over it' ],
    [ q{sub d { my ($v) = @_; return $v eq "x" ? "eq" : "ne" } print d("x"), " ", d([1]), "\n";}, 'a reference compared as a string (r82p1)' ],
    [ q{my $a = [1]; my $b = $a; my $c = [1]; print $a == $b ? "same" : "differ", " ", $a == $c ? "same" : "differ", " ", "$a" eq "$b" ? "y" : "n", "\n";}, 'a reference as a number is its address' ],
    [ q{my @a = (1, 2); my $r = \@a; sub f { my $x = shift; $x->[0] = 9; return 0 } my $before = $a[0]; f($r); print "$before $a[0]\n";}, 'a read kept across a call storing through a reference' ],
) {
    my ($src, $name) = @$case;
    $LAST_LL = '';
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
    like($LAST_LL, qr/^; chalk T2/m, "$name: lowered through T2");
}

# PERL'S ANSWER, OR REFUSED: a copy across a store; through an element.
for my $case (
    [ q{sub f { my ($h) = @_; my @p = @$h; $h->[0] = 2; return "$p[0] $h->[0]" } print f([1]), "\n";}, 'my @p = @$h is a copy (pvm 236)' ],
    [ q{my $m = [[1, 2], [3]]; print $m->[0][1], scalar(@{$m->[1]}), "\n";}, 'nested through an element' ],
    [ q{my $m = [[1, 2], [3]]; my $x = $m->[0]; my $y = $m->[1]; print $x->[1], scalar(@$y), "\n";}, 'nested, through variables (B::SoN folds them)' ],
    [ q{my @a; $a[1][0] = 5; print scalar(@a), " ", $a[1][0], "\n";}, 'a store through an undef element' ],
) {
    my ($src, $name) = @$case;
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (defined $got) { is($got, perl_says($pl, {}), "$name: perl's answer") }
    else { like($@, qr/GAP|refused at run time|^lower: /, "$name: refused by name") }
}

done_testing;
