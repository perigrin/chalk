# ABOUTME: A callee that writes $_[N] writes its caller's argument: the variable or the
# ABOUTME: element it aliases, stored back after the inline -- B::SoN -> chalk -> lli == perl.
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

# `$_[N] = ...` IS A STORE TO THE CALLER'S ARGUMENT. Inlining binds @_ to
# an array of the arguments; a callee that writes it reads that array, and
# each written element is stored back to what it aliases -- a variable kept
# in memory, or an element (pvm subroutines.md and chalk-found-gaps.md,
# refused as "callee writes $_[N]"). A temporary keeps no store; a literal
# is read-only in perl, which dies, and is refused.
for my $case (
    [ q{sub g { $_[0] = 5 } my $c = 1; g($c); print "$c\n"; my %h = (a => 1); g($h{a}); print "$h{a}\n";}, "5\n5\n", 'a variable and a hash element' ],
    [ q{sub bump_alias { $_[0]++ } sub bump_copy { my ($n) = @_; $n++ } my ($aliased, $untouched) = (1, 1); bump_alias($aliased); bump_copy($untouched); print "$aliased $untouched\n";}, "2 1\n", 'an alias and a copy' ],
    [ q{sub bump { $_[0]++ } my @a = (1, 2); for my $x (@a) { bump($x) } print "@a\n";}, "2 3\n", 'through a foreach alias' ],
    [ q{sub g { $_[0] = 9; return $_[0] + 1 } my $x = 1; print g($x + 1), " $x\n";}, "10 1\n", 'a temporary, and a read after the write' ],
    [ q{sub two { $_[1] = "b" } my ($p, $q) = ("x", "y"); two($p, $q); print "$p$q\n";}, "xb\n", 'the second argument' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

my $err = do { local $@; eval { through_llvm(q{sub g { $_[0] = 5 } g(3); print "x\n";}) }; $@ };
like($err, qr/GAP: .*a literal/, 'a write to a literal is refused by name');

done_testing;
