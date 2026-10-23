# ABOUTME: push appends its values to an array, growing it, and returns the new count:
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

# PUSH WAS NOT LOWERED AT ALL -- "cannot lower op=Call builtin push", the
# commonest builtin refusal in the pvm corpus (11 cases). It appends through
# the same grow-and-store a map's accumulator does, and is a memory version:
# a read of the array after it is taken after it.
for my $case (
    [ q{my @a = (10); push @a, 4, 5; print scalar(@a), " $a[2]\n";}, "3 5\n", 'push two values' ],
    [ q{my @r; for my $i (1 .. 3) { push @r, $i * 2 } print "@r\n";}, "2 4 6\n", 'push in a loop onto an empty array' ],
    [ q{my @a = (1); my $n = push @a, 7; print "$n $a[1]\n";}, "2 7\n", 'push returns the new count' ],
    [ q{my @a = (10); my @t = (20, 30); push @a, @t; print scalar(@a), " $a[2]\n";}, "3 30\n", 'push an array' ],
    [ q{my @k; push @k, qw(a b c); print "@k\n";}, "a b c\n", 'push strings' ],
    [ q{my @a = (1, 2); my $x = $a[1]; push @a, 9; print "$x $a[2]\n";}, "2 9\n", 'a read before a push is the value then' ],
    # "@a" IS join($", @a): over a literal it arrives flattened, the
    # separator then each element, and $" is perl's " " until written.
    [ q{my @a = (1, 2); print "@a\n";}, "1 2\n", 'an array interpolated' ],
    # A SUB'S `my @p` IS FRESH EACH CALL: inlined twice, it was one array
    # built at the program's entry, so the second call saw the first's pushes.
    [ q{sub mk { my @p; push @p, 1; push @p, 2; return "@p" } print mk(), mk(), "\n";}, "1 21 2\n", "a sub's empty array is fresh per call" ],
    # A PUSH IN AN ARM onto an array built before the if: the array was first
    # lowered inside the arm, and the read after the merge used a value that
    # arm does not dominate -- lli rejected the module.
    [ q{my $n = 1; $n = $n + 0; my @a = (1, 2); if ($n) { push @a, 3 } print scalar(@a), "\n";}, "3\n", 'a push in an arm, read after the merge' ],
    [ q{sub f { my $n = shift; my @a = (1, 2); if ($n) { push @a, 3 } return scalar(@a) } print f(1), f(0), "\n";}, "32\n", "a push in an arm of a sub's body" ],
    # A HASH WRITTEN IN AN ARM, READ AFTER IT. "The literal speaks for an
    # unwritten array only" took the element's type from neither the literal
    # nor the stores once memory had moved; a %HashEntry has no tag, so the
    # read was tagged Opaque and printed nothing for perl's 3 (b019b022).
    [ q{my %h = (a => 1); my $n = 1; $n = $n + 0; if ($n) { $h{a} = $h{a} + 2 } print "$h{a}\n";}, "3\n", 'a hash element stored in an arm, read after it' ],
    # The same hole held shift before push existed (red at e1a15d3a).
    [ q{my $n = 1; $n = $n + 0; my @a = (1, 2); if ($n) { shift @a } print scalar(@a), "\n";}, "1\n", 'a shift in an arm, read after the merge' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
