# ABOUTME: A block eval catches a die in its body -- inline, in an arm, or in a sub it
# ABOUTME: inlines -- and sets $@ as perl does: B::SoN -> chalk -> lli == perl.
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

# A BLOCK EVAL IS A BRANCH. chalk inlines what the body calls, so every die
# the body can reach is in the function being lowered: it stores $@ and
# jumps to the eval's end, where the value is undef. No unwinder is needed.
# perl clears $@ when the eval starts and when it ends without dying.
for my $case (
    [ q{my $r = eval { 1 }; print defined $r ? "r=$r [$@]\n" : "died\n";}, "r=1 []\n", 'a body that does not die' ],
    [ q{my $r = eval { die "boom\n"; 1 }; print defined $r ? "ran\n" : "died: $@";}, "died: boom\n", 'a die in the body' ],
    [ q{eval { print "a\n"; die "b\n"; print "c\n" }; print "after $@";}, "a\nafter b\n", 'a void eval stops at its die' ],
    [ q{my $x = $ENV{NO_SUCH_VAR} // 1; my $r = eval { if ($x) { die "arm\n" } 2 }; print defined $r ? "r=$r\n" : "died: $@";}, "died: arm\n", 'a die in an arm' ],
    [ q{sub f { die "in f\n" if $_[0]; 7 } my $r = eval { f(1) }; print defined $r ? "r=$r\n" : "died: $@"; my $s = eval { f(0) }; print "$s\[$@]\n";}, "died: in f\n7[]\n", 'a die in a sub the body calls' ],
    [ q{$@ = "x"; eval { print "in[$@]\n"; 1 }; eval { die "y\n" }; eval { 1 }; print "out[$@]\n";}, "in[]\nout[]\n", 'an eval clears $@' ],
    [ q{print defined $@ ? "defined\n" : "undef\n"; my $r = eval { 1 };}, "defined\n", '$@ starts as ""' ],
    [ q{my $i = eval { my $j = eval { die "x\n"; 1 }; print defined $j ? "j\n" : "inner caught $@"; 2 }; print "i=$i [$@]\n";}, "inner caught x\ni=2 []\n", 'nested evals: $@ is what the last one left' ],
    [ q{my $s; my $r = eval { eval { die "a\n" }; $s = $@; eval { 1 }; 1 }; print "[$s]\n";}, "[a\n]\n", 'a read of $@ is taken where it is made' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

# IN LIST CONTEXT a die gives the empty list, not undef: refused by name.
{
    my $got = eval { through_llvm(q{sub f { die "x\n" if $_[0]; 7 } print eval { f(0) }, "\n";}) };
    like($@, qr/GAP: .*list or caller context/, 'a list-context eval that can die is refused');
}

# A DIE IN A BODY THAT IS NOT INLINED -- a class method, lowered as its own
# function -- would end the program where perl catches it: refused by name.
{
    my $got = eval { through_llvm(q{use v5.42; use feature 'class'; no warnings; class C { method m { die "m\n" } } my $r = eval { C->new->m; 1 }; print defined $r ? "ran\n" : "died: $@";}) };
    like($@, qr/GAP: .*inside a block eval/, 'a method call in an eval is refused');
}

# A DIE PERL MAKES ITSELF -- a deref of what is not a SCALAR reference -- has
# a message with its file and line in it: inside an eval, refused by name.
{
    my $got = eval { through_llvm(q{my $x = $ENV{NO_SUCH_VAR} // [1]; my $r = eval { my $v = $$x; 1 }; print defined $r ? "ran\n" : "died\n";}) };
    like($@, qr/GAP: .*inside a block eval/, 'a deref that can die in an eval is refused');
}

# ONLY $@ IS A GLOBAL HERE. Another punctuation variable is perl's to set
# ($^W is 0, $^O the OS): read from an empty global it printed "", refused.
{
    eval { through_llvm(q{$::w = $^W; print $::w, "\n";}) };
    like($@, qr/GAP: /, 'a read of $^W is refused');
}

# AN EVAL IN A LOOP BODY is opened there as a branch (the body is lowered
# statement by statement through process_control_node, as an arm is): perl's
# answer. Anything still not lowered is refused by name -- never a die sent
# to another eval's end or out of the program.
for my $case (
    [ q{for my $k (1 .. 3) { my $r = eval { die "k$k\n" if $k == 2; $k }; print defined $r ? "r$r\n" : "caught $@"; }}, 'an eval in a loop' ],
    [ q{for my $k (1 .. 3) { eval { die "k\n" if $k == 2 }; print "$k\n"; }}, 'a void eval in a loop' ],
) {
    my ($src, $name) = @$case;
    my $want = qx($^X -e '$src');
    my $got  = eval { through_llvm($src) };
    ok(( defined $got && $got eq $want ) || $@ =~ /GAP: /, "$name: perl's answer, or refused by name")
        or diag "got: " . ( $got // 'undef' ) . " want: $want $@";
}

# SO IS A CALL IN SUCH AN EVAL: the sub's die is a branch to that eval's
# end, where perl's try or eval catches it (pvm 173).
for my $case (
    [ q{use v5.42; no warnings; sub g { die "no\n" if $_[0] == 3; return $_[0] * 2 } sub f { my @out; for my $s (@_) { my $c; try { $c = g($s) } catch ($e) { return "R@out" } push @out, $c } return "@out" } print f(1, 2, 3, 4), " ", f(1, 2), "\n";}, 'a try in a loop, calling a sub that dies' ],
    [ q{sub g { die "no\n" if $_[0] == 2; $_[0] } my $n = 0; for my $k (1 .. 3) { my $r = eval { g($k) }; $n++ if defined $r } print "$n\n";}, 'an eval in a loop, calling a sub that dies' ],
) {
    my ($src, $name) = @$case;
    my $want = qx($^X -e '$src');
    my $got  = eval { through_llvm($src) };
    ok(( defined $got && $got eq $want ) || $@ =~ /GAP: /, "$name: perl's answer, or refused by name")
        or diag "got: " . ( $got // 'undef' ) . " want: $want $@";
}

# A DIE OF A LIST joins it: only a one-argument die is lowered.
{
    eval { through_llvm(q{my $r = eval { die "a\n", "b\n" }; print "[$@]";}) };
    like($@, qr/GAP: .*argument/, 'a die of two arguments is refused');
}

# A MESSAGE WITHOUT ITS NEWLINE gets " at FILE line N." from perl, which
# this lowering does not know: refused by name, not answered wrong.
{
    my $got = eval { through_llvm(q{my $r = eval { die "no newline" }; print "died: $@";}) };
    like($@, qr/GAP: .*newline/, 'a message perl would extend is refused');
}

done_testing;
