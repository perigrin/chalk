# ABOUTME: A foreach over @_ aliases each argument: a ternary over the alias and the
# ABOUTME: element, lowered as branches -- B::SoN -> chalk -> lli == perl, or refused by name.
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

# A FOREACH OVER @_ ALIASES ITS ELEMENTS: B::SoN spells the iterator
# `exists $_[$i] ? \$_[$i] : undef`, and each read `exists ? $$alias :
# $_[$i]` -- a ternary whose join is a Scalar, refused outright ("TernaryExpr
# with repr=Scalar", 7 pvm cases). It is BRANCHED, not a select: the deref
# of an alias not made is a load through null. The alias is the element's
# slot, which an array that may grow would move, so that is refused.
for my $case (
    [ q{sub id { $_[0] } sub keep { my $out = ""; for my $x (@_) { next unless id($x) > 1; $out .= $x } return $out } print keep(1, 2, 3), "\n";}, "23\n", 'a foreach over @_ handing its alias to a call' ],
    [ q{sub last_is_for { my @seen; for my $x (@_) { push @seen, $x * 2 } } my @f = last_is_for(1, 2); my $s = last_is_for(3); print scalar(@f), "[", $f[0], "][", $s, "]\n";}, "1[][]\n", 'a sub ending in a foreach over @_' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

for my $case (
    [ q{my @a; $a[1] = 1; my $s = ""; for my $x (@a) { $a[0] = 5; $s .= $x // "u" } print $s, "\n"}, qr/GAP: a reference to an element of an array that may grow/, 'an alias into an array a store may grow' ],
    [ q{my %in = (a => [[1, 2], 3], b => [4]); my @dead; push @dead, qw(a b); my @seen; for my $d (@dead) { for my $i ($in{$d}->@*) { if (ref $i) { for my $e ($i->@*) { push @seen, "$d$e" } } else { push @seen, "$d$i" } } } print "@seen\n";}, qr/GAP: an if is reached again inside its own arm/, 'an arm walk that cycles ends, refused' ],
) {
    my ($src, $re, $name) = @$case;
    my $err = do { local $@; eval { through_llvm($src) }; $@ };
    like($err, $re, "$name: refused by name");
}

done_testing;
