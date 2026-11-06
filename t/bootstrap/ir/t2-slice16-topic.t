# ABOUTME: T2 slice 16 -- $_ aliased to each element (map, grep, for without a variable): its
# ABOUTME: reads and writes are the element's; map/grep build their list; $_ elsewhere is refused.
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
    [ q{sub shout { return uc $_[0] } my @loud = map { shout($_) } qw(a b c); print "@loud\n";}, 'map through a sub (pvm 034)' ],
    [ q{my @a = (1, 2, 3, 4); my @d = map { $_ * 2 } @a; my @e = grep { $_ % 2 == 0 } @a; print "@d|@e|", scalar(@e), "\n";}, 'map and grep' ],
    [ q{my @a = (1, 2, 3); for (@a) { $_ *= 10 } print "@a\n";}, 'for without a variable writes through $_ into the array' ],
    [ q{my $s = 0; for (1 .. 4) { $s += $_ } print "$s\n";}, 'for over a range' ],
    [ q{sub f { my ($s) = @_; return uc($s) . lc($s) . ucfirst(lc $s) . lcfirst($s) } print f("aBc"), f(""), "\n";}, 'uc, lc, ucfirst, lcfirst' ],
) {
    my ($src, $name) = @$case;
    $LAST_LL = '';
    my ($got, $pl) = eval { through_llvm($src, {}) };
    is($got, perl_says($pl // write_pl($src), {}), "$name: perl's answer") or diag $@;
    like($LAST_LL, qr/^; chalk T2/m, "$name: lowered through T2");
}

# $_ READ WHERE NO LOOP HERE SET IT: perl's answer, or refused.
for my $src (q{sub f { return $_ * 2 } my @r = map { f() } 1, 2; print "@r\n";}, q{$_ = 5; for (1, 2) { } print "$_\n";}) {
    my ($got, $pl) = eval { through_llvm($src, {}) };
    if (defined $got) { is($got, perl_says($pl, {}), "\$_ elsewhere: perl's answer") }
    else { like($@, qr/GAP|refused at run time|^lower: /, "\$_ elsewhere: refused by name") }
}

done_testing;
