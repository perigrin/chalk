# ABOUTME: `my (...) = @_` into a variable kept in memory (passed on to another sub)
# ABOUTME: stores each argument there: B::SoN -> chalk -> lli == perl.
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

# The targets were bound to the arguments, and the assignment reached the
# lowering as a value of @_, which has none: refused (pvm 102 154 203 220).
# Kept in memory, a later read of the target loads the location -- the
# argument has to be stored there.
for my $c (
    [ q{sub g { my ($v) = @_; $v } sub run { my ($in) = @_; g($in) } print run("a"), "\n";} ],
    [ q{sub g { $_[1] + 2 } sub run { my ($in) = @_; my $pos = 0; $pos = g($in, $pos); return $pos } print run("a"), "\n";} ],
    [ q{sub g { $_[0] } sub run { my ($p, $q) = @_; g($p) . (defined $q ? "d" : "u") } print run("x"), run("y", 1), "\n";} ],
    [ q{sub g { $_[1] + 2 } sub run { my ($in) = @_; my $pos = 0; while ($pos < 5) { $pos = g($in, $pos) } return $pos } print run("a"), "\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# WRITTEN AFTER IT IS BOUND: `.=` on a target nothing typed is refused by
# another cause; it must not be a different answer.
{
    my $src = q{sub g { $_[0] } sub run { my ($p) = @_; $p .= "!"; g($p) } print run("x"), "\n";};
    my $got = eval { through_llvm($src) };
    if (defined $got) { is($got, qx($^X -e '$src'), "perl's answer: $src") }
    else { like($@, qr/\S/, "refused: $src") }
}

done_testing;
