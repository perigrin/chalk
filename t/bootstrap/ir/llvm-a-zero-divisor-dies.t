# ABOUTME: Division and modulus by zero die, as perl's do, rather than give Inf or crash:
# ABOUTME: B::SoN -> chalk -> lli exits 255 where perl does; inside an eval, refused by name.
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

# The whole program through B::SoN, chalk's pipeline and lli: its stdout and
# exit status.
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
    my $out = qx($LLI $ll 2>/dev/null);
    return ($out, $? >> 8);
}

# A ZERO DIVISOR DIES. perl stops with "Illegal division by zero" (exit 255,
# nothing more on stdout); chalk's fdiv gave Inf and went on, and srem by
# zero is undefined in LLVM.
for my $case (
    [ q{my $z = $ENV{NO_SUCH_VAR} // 0; print "a\n"; print 1 / $z, "\n"; print "b\n";}, 'division' ],
    [ q{my $z = $ENV{NO_SUCH_VAR} // 0; print "a\n"; print 7 % $z, "\n"; print "b\n";}, 'modulus' ],
) {
    my ($src, $name) = @$case;
    my ($out, $rc) = eval { through_llvm($src) };
    is($out, "a\n", "$name by zero: stops where perl does") or diag $@;
    is($rc, 255, "$name by zero: perl's exit status");
}

# A nonzero divisor still divides.
{
    my ($out, $rc) = eval { through_llvm(q{my $d = $ENV{NO_SUCH_VAR} // 4; print 6 / $d, " ", 7 % $d, "\n";}) };
    is($out, "1.5 3\n", 'a nonzero divisor divides') or diag $@;
}

# INSIDE AN EVAL perl catches it with " at FILE line N." in $@, which this
# lowering does not know: refused by name. A literal nonzero divisor cannot die.
{
    eval { through_llvm(q{sub d { 1 / $_[0] } my $z = $ENV{NO_SUCH_VAR} // 0; my $r = eval { d($z) }; print defined $r ? "ran\n" : "died\n";}) };
    like($@, qr/GAP: .*zero.*eval/, 'a division that may be by zero, in an eval, is refused');
    my ($out) = eval { through_llvm(q{sub h { $_[0] / 2 } my $x = $ENV{NO_SUCH_VAR} // 6; my $r = eval { h($x) }; print "$r\n";}) };
    is($out, "3\n", 'a division by a literal in an eval is lowered') or diag $@;
    # An UNUSED division still dies in perl; B::SoN drops it from the graph,
    # so it says so on the eval instead.
    eval { through_llvm(q{my $z = $ENV{NO_SUCH_VAR} // 0; my $r = eval { my $q = 1 / $z; 1 }; print defined $r ? "ran\n" : "died\n";}) };
    like($@, qr/GAP: .*eval.*may die/, 'an unused division that may be by zero, in an eval, is refused');
    # So with a reference to an element: one before the start dies.
    eval { through_llvm(q{my @a = (1, 2); my $r = eval { my $p = \$a[-5]; 1 }; print defined $r ? "ran\n" : "died\n";}) };
    like($@, qr/GAP: .*eval.*may die/, 'an unused element reference, in an eval, is refused');
    # In a sub the eval calls, the eval cannot see it: chalk refuses it there.
    eval { through_llvm(q{sub g { my @a = (1, 2); my $p = \$a[$_[0]]; $$p // 'u' } my $i = $ENV{NO_SUCH_VAR} // -5; my $r = eval { g($i) }; print defined $r ? "ran\n" : "died\n";}) };
    like($@, qr/GAP: .*inside a block eval/, 'an element reference in a sub an eval calls is refused');
}

done_testing;
