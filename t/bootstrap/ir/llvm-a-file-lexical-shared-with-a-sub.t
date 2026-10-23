# ABOUTME: A file-level `my` a named sub closes over is one variable, read and written from
# ABOUTME: both graphs: through B::SoN -> chalk -> lli == perl.
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

# A SHARED FILE LEXICAL IS A LOCATION, not an SSA value: B::SoN reads it
# through memory (PadAccess shared, on a memory version) and stores it with
# an Assign, in the program and in every sub that closes over it. chalk
# refused every one ("Assign lhs must be a PadAccess(VarDecl) ... got
# MemStart", 60 pvm corpus cases). It is one module global, boxed in a Slot.
for my $case (
    [ q{my $count = 0; sub inc { if ($count < 5) { $count = $count + 1 } return 0 } inc(); inc(); print "$count\n";}, "2\n", 'a sub increments a file counter under a branch' ],
    [ q{my $base = 10; sub add { my $n = shift; return $base + $n } print add(1), "\n";}, "11\n", 'a sub reads a file lexical' ],
    [ q{my $s = "a"; sub app { $s = $s . "b"; return 0 } app(); app(); print "$s\n";}, "abb\n", 'a sub appends to a file string' ],
    [ q{{ my $c = 1; sub a { $c = $c + 1; return $c } } { my $c = 10; sub b { $c = $c + 1; return $c } } print a(), " ", b(), " ", a(), "\n";}, "2 11 3\n", 'two file lexicals of one name' ],
    [ q{my $n = 0; sub bump { $n = $n + 1; return $n } for my $i (1 .. 3) { bump() } print "$n\n";}, "3\n", 'a shared counter across a loop' ],
    # A SLOT CARRIES ITS DEFINED BIT. `defined` over a Scalar answered true
    # unread, and an unassigned shared `my $k` was "def".
    [ q{my $k; sub f { return defined($k) ? "def" : "undef" } print f(), "\n"; $k = 1; print f(), "\n";}, "undef\ndef\n", 'defined over a shared lexical, before and after a store' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
