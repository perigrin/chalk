# ABOUTME: perl's IV/UV/NV forms where chalk might deviate under the 2026-11-16 ruling: T2
# ABOUTME: matches perl unless chalk's answer is the provably exact one (Harness::Deviation).
use 5.42.0;
use utf8;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Harness::TapDiff;

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.t', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

# THE RULE (perigrin, 2026-11-16; Chalk::CodeGen::Harness::Deviation). perl's
# IV/UV/NV forms are its implementation, not the language, and they leak:
# chalk may print other than perl where its answer is PROVABLY CORRECT -- the
# reason states the proof, the output is never less exact or less consistent
# than perl's, and "chalk has not yet" is no ground. A deviation is declared,
# with the exact output chalk must print; anything undeclared is perl's.
# The UV work (T2: a UV in the scalar) left two places measured here.

# 1. A STRING THAT IS NO INTEGER TIMES A WHOLE NV: "1.0" * 1e15. pp_multiply
# reads "1.0" as no integer (grok_number: a fraction part), so the product is
# the NV, printed %.15g -- 1e+15. T2 reads it the same way and prints the
# same, so there is NO deviation to declare: chalk prints perl's output here,
# in every form measured (a literal, a variable, either order, *=, an array
# element, a sub's argument, a value T2 holds in a %Slot).
{
    my $src = join '', map { "$_\n" }
        'my $s = $ENV{CHALK_NO_SUCH} // "1.0";',
        'print "1.0" * 1e15, " ", $s * 1e15, " ", 1e15 * $s, " ", $s * "1e15", "\n";',
        'my $t = $s; $t *= 1e15; my @a = ($s); sub f { $_[0] * 1e15 } print "$t ", $a[0] * 1e15, " ", f($s), "\n";',
        'print $s * 1234567890123456, " ", ($ENV{CHALK_NO_SUCH} // "1.5") * 1e15, " ", $s * 1e17, "\n";';
    my $r = tap($src);
    is $r->{verdict}, 'SAME', '"1.0" * 1e15 and kin: perl\'s output, no deviation' or diag explain $r;
}

# 2. AN NV PERL HAS ALREADY READ AS AN INTEGER. sv_2iv_flags on an NV that is
# a whole number sets IOK as well as NOK, and from then on perl prints it from
# the IV -- `"$x"`, `-$x` (pp_negate's SvIOK test), `$x++`'s old value -- WHOLE:
# 1234567890123456. Read as no integer, the same value prints from the NV,
# %.15g: 1.23456789012346e+15. T2 keeps no such history and prints the
# rounded double in both. PERL'S IS THE EXACT VALUE (the NV holds
# 1234567890123456 exactly; %.15g drops a digit), so chalk's answer is the
# less exact one: ground (b) does not hold and this may NOT be declared. It is
# a defect -- "chalk has not yet" -- pinned here as perl's output.
{
    my $src = join '', map { "$_\n" }
        'my $x = $ENV{CHALK_NO_SUCH} // "1.0"; $x *= 1234567890123456;',
        'my $t = $x + 0;',
        'print "$x ", -$x, "\n";';
    my $r = tap($src);
    TODO: {
        local $TODO = "perl prints an NV it has read as an integer whole (IOK); T2 keeps no such history and "
            . "prints %.15g -- a defect, not a deviation: perl's is the exact value";
        is $r->{verdict}, 'SAME', 'an NV perl read as an integer: printed whole, as perl' or diag explain $r;
    }
    # Unread, perl rounds as T2 does: no deviation either way.
    $r = tap(qq{my \$x = \$ENV{CHALK_NO_SUCH} // "1.0"; \$x *= 1234567890123456; print "\$x ", -\$x, "\\n";\n});
    is $r->{verdict}, 'SAME', 'an NV never read as an integer: %.15g, as perl' or diag explain $r;
}

done_testing;
