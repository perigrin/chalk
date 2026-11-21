# ABOUTME: A program T2 lowers from B::SoN's wire v1 it lowers from wire v2 too, printing perl's
# ABOUTME: output: the cases the v2 census lost (an Impl class linked in, a foreach alias's reference).
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
require Chalk::CodeGen::Pipeline;

# run($cmd) -> [stdout, stderr, exit code]
sub run ($cmd) {
    my (undef, $ef) = tempfile(UNLINK => 1);
    my $out = qx($cmd 2>$ef);
    my $code = $? >> 8;
    my $err = do { local (@ARGV, $/) = $ef; <> } // '';
    return [ $out, $err, $code ];
}

# lower($pl, $wire) -> (ll or undef, why): through T2 alone, from wire $wire
sub lower ($pl, $wire) {
    my $json = qx($^X -I$SON -MO=-q,SoN,json,wire=$wire $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $u = $units->[0] // {};
    my $ll = !$err && $u->{ok} && ( $u->{path} // '' ) eq 't2' ? $u->{ll} : undef;
    return ($ll, $err // $u->{path_why} // $u->{err});
}

# WHY. The census at wire 2 lost 14 cases v1 lowers (the baseline note,
# section 10), each by a T2 refusal; two causes.
#
# AN IMPL CLASS IS LINKED IN AT THE PROGRAM'S WIRE. A program that names
# %SIG, %INC or a stash gets chalk's own metaobject class linked into its
# wire (Chalk::Impl::link_json), which B::SoN compiled at wire 1 whatever the
# program's was: v1 graphs inside a v2 wire are read with their memory as an
# input (a bless of "one argument" was bless, its class and its memory; a
# PadAccess's memory input made it no location).
#
# A FOREACH ALIAS'S REFERENCE IS NO VERSION. On v2 every pinned read names
# the memory it follows; only one taken where it stands (`\$a[$i]` ordered
# on the array's memory) is a memory version, mem_out. Asking "has it a
# memory edge" took the alias's for one taken where it stands.
my @cases = (
    [ q{local $SIG{__WARN__} = sub { }; my @g = (warn "a", "b"); my @c = (warn("a"), "b"); print scalar @g, scalar @c, "\n";},
      'a warn handler: %SIG\'s class linked in' ],
    [ q{require strict; print "inc: ", ($INC{"strict.pm"} ? "yes" : "no"), "\n";},
      'a read of %INC: its class linked in' ],
    [ q{use POSIX (); print "stash: ", ($main::{"POSIX::"} ? "yes" : "no"), "\n";},
      'a read of the main stash: its class linked in' ],
    [ q{sub f { my ($v) = @_; return ref $v ? "r" : "s" } for my $x (undef, [1]) { print f($x), " " } print "\n";},
      'a foreach alias handed to a sub, at an index not a constant' ],
    # (B::SoN's: an append's result read with its store as a value input on v2 -- probe ev10)
    [ q{use feature "try"; no warnings; my $x = 1; try { $x = 2; die "t\n"; $x = 3 } catch ($e) { $x .= "c" } print "$x\n";},
      'an append to a `my` in a catch block' ],
    # THE MEMORY PHI AT A SUB'S EXITS (fields.exits): named only by the Return's mem_in.
    [ q{our $g = 0; sub f { my ($x) = @_; if ($x) { $g = $x; return 1 } $g = -1; return 2 } my $a = f(1); my $b = $g; my $c = f(0); print "$a $b $c $g\n";},
      'a sub whose exits merge their memory' ],
    [ q{my @s; sub r { my ($n) = @_; if ($n <= 0) { push @s, "z"; return 0 } push @s, $n; return $n + r($n - 1) } print r(3), " @s\n";},
      'a recursive sub whose exits merge their memory' ],
    # REVIEW FOCUS 3 (the plan): a call that is a value and a memory version,
    # merged by a value Phi and a memory Phi at one Region.
    [ q{our $n = 0; sub f { $n++; return $n } sub g { $n += 10; return $n } my $x = @ARGV ? f() : g(); my $y = @ARGV ? g() : f(); print "$x $y $n\n";},
      'two calls, each a value and a version, merged at one Region' ],
);
for my $case (@cases) {
    my ($src, $name) = @$case;
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $want = run("$^X $pl");
    for my $wire (1, 2) {
        my ($ll, $why) = lower($pl, $wire);
        ok(defined $ll, "$name: wire $wire: lowered through T2") or diag $why;
        next unless defined $ll;
        my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        print $lf $ll; close $lf;
        my $got = run("timeout 20 $LLI $llp");
        is($got->[0], $want->[0], "$name: wire $wire: perl's output");
        is($got->[2], $want->[2], "$name: wire $wire: perl's exit code");
    }
}
done_testing;
