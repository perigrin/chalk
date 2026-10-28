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

# The nested-loop case once refused as "an if is reached again inside its
# own arm": the arm walk cycled because the JSON loader interned two pinned
# reads of one content into one node. Kept apart, the walk ends, and the
# program is refused further on (a value nothing typed).
# An alias lives one pass of its loop: what grows the array before the
# loop, or stores at 0 in it (the array has an element there), does not move
# it (pvm 187 190 198).
for my $case (
    [ q{sub f { my @a; $a[1] = 1; my $s = ""; for my $x (@a) { $a[0] = 5; $s .= $x // "u" } print $s, (exists $a[0] ? "e" : "n"), "\n" } f();}, 'a store at 0 in the loop, one past before it' ],
    [ q{sub f { my @a; push @a, 1, 2; my $s = ""; for my $x (@a) { $s .= $x; $_ = 0 for @a } return "$s|@a" } print f(), "\n";}, 'a push before the loop, an inner loop storing through aliases' ],
    [ q{my @a = (1); push @a, 2; my $s = ""; for my $x (@a) { $x *= 10 } push @a, 3; print "@a\n";}, 'a push after the loop' ],
) {
    my ($src, $name) = @$case;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

# A read through the alias before a store to its element in the same pass
# reads what was there -- it once read the store (rw1 rw2 rw3).
for my $case (
    [ q{my @a = (1, 2); my $s = ""; for my $x (@a) { $s .= $x; $a[1] = 0; $a[0] = 0 } print "$s|@a\n";}, 'read, then stores to both elements' ],
    [ q{sub f { my @a = (1, 2); my $s = ""; for my $x (@a) { $s .= $x; $a[0] = 0 } return "$s|@a" } print f(), "\n";}, 'in a sub' ],
    [ q{my @a = (1, 2); my $s = ""; for my $x (@a) { my $y = $x; $a[0] = 9; $s .= $y } print "$s\n";}, 'a copy, then a store' ],
) {
    my ($src, $name) = @$case;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    if (!defined $got && $@ =~ /GAP: /) { pass("$name: refused by name") }
    else { is($got, $want, "$name: perl's answer") or diag $@ }
}

# What grows the array while an alias into it lives moves the alias.
for my $case (
    [ q{my @a = (1, 2); my $s = ""; for my $x (@a) { push @a, 3 if @a < 4; $s .= $x } print "$s\n"}, qr/GAP: a reference to an element of an array that may grow/, 'a push in the loop' ],
    # B::SoN refuses this one today; chalk refuses it too, should it arrive.
    [ q{my @a = (1); my @r; for my $x (@a) { push @r, \$x } push @a, 2 .. 9; ${$r[0]} = 7; print "$a[0]\n"}, qr/\A(?:load|lower):/, 'an alias that escapes its pass' ],
) {
    my ($src, $re, $name) = @$case;
    my $err = do { local $@; eval { through_llvm($src) }; $@ };
    like($err, $re, "$name: refused by name");
}

# THE NESTED LOOPS once refused as an untyped value: the innermost loop's
# memory merge took a builtin (push) as its memory and was read as a value.
# It is perl's answer.
{
    my $src = q{my %in = (a => [[1, 2], 3], b => [4]); my @dead; push @dead, qw(a b); my @seen; for my $d (@dead) { for my $i ($in{$d}->@*) { if (ref $i) { for my $e ($i->@*) { push @seen, "$d$e" } } else { push @seen, "$d$i" } } } print "@seen\n";};
    my $want = qx($^X -e '$src');
    is(eval { through_llvm($src) }, $want, "nested loops over an alias and a deref: perl's answer") or diag $@;
}

done_testing;
