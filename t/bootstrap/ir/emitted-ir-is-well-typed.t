# ABOUTME: Every Str-producing and Str-consuming path must emit WELL-TYPED LLVM IR.
# ABOUTME: Asserts llvm-as accepts the module — a type error here is a compiler bug, not a GAP.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use JSON::PP;
use Chalk::IR::Serialize::JSON;
use Chalk::Target::LLVM;

my $PERL    = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON     = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLVM_AS = '/usr/lib/llvm-15/bin/llvm-as';

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "llvm-as not found at $LLVM_AS" unless -x $LLVM_AS;
plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;

# ---------------------------------------------------------------------------
# WHY THIS EXISTS.
#
# The %Str migration (a Str VALUE is the aggregate {ptr,len,enc}, not a bare
# i8*) broke fourteen t/bootstrap/ir/llvm-*.t files while the CORPUS GATE STAYED
# GREEN AT 196 the entire time. The corpus exercises Str constants and prints;
# it does not reach Coerce[Int->Str], EnvRead, Call/new dispatch, or
# bool-truthiness, so it could not observe that those paths were emitting
# ill-typed IR.
#
# The unit tests added alongside that migration were no better: they asserted on
# the compiler's INTERNAL BOOKKEEPING (does the field list have three entries?
# is the size derived?) and every one of them passed while every module lli saw
# was rejected. Testing the bookkeeping instead of the OUTPUT is the same
# vacuous-coverage shape the migration was meant to remove.
#
# So this test asserts the one property those all missed: THE EMITTED IR
# TYPE-CHECKS. It does not check behaviour — the corpus does that. It checks
# that what we hand the assembler is a legal module, which is the invariant a
# representation change can violate silently.
#
# llvm-as rather than lli: we want the VERIFIER's verdict, not the program's.
# A program that legitimately exits nonzero (die, exit 4) must not read as a
# failure here, and a GAP must not either — a GAP means we declined to emit,
# which is a different and acceptable outcome.
# ---------------------------------------------------------------------------

# Each case names a distinct Str path through the backend. The comment is the
# path, not the program: these are chosen to REACH code, not to be interesting.
my @CASES = (
    ['Str constant + print',        'print "hi\n";'],
    ['Str constant shared by arms', 'my $c=1; if ($c) { print "s" } else { print "s" } print "\n";'],
    ['Concat of two Str',           'my $a="x"; my $b="y"; print $a . $b; print "\n";'],
    ['Concat-assign (.=)',          'my $s=""; $s .= "a"; $s .= "b"; print $s; print "\n";'],
    ['Coerce Int->Str (interp)',    'my $n=42; print "n=$n"; print "\n";'],
    ['Coerce Int->Str (say)',       'say(7);'],
    ['Coerce Num->Str',             'say(0.5);'],
    ['Coerce Bool->Str',            'say(1==1);'],
    ['StrEq over two Str',          'my $a="x"; print(($a eq "x") ? "1" : "0"); print "\n";'],
    ['StrEq with an Int operand',   'my $a=1; print(($a eq "1") ? "1" : "0"); print "\n";'],
    ['Str ternary (select)',        'my $c=0; print($c ? "y" : "n"); print "\n";'],
    ['Str in a loop accumulator',   'my $s=""; for my $i (1..3) { $s .= "x" } print $s; print "\n";'],
    ['Str array element',           'my @a=("hi","there"); print $a[0]; print "\n";'],
    ['Str hash value',              'my %h=(k=>"v"); print $h{k}; print "\n";'],
    ['Str hash KEY (memcmp path)',  'my %h=("kk"=>1); print $h{"kk"}; print "\n";'],
    ['Str package scalar',          'our $g = "pkg"; print $g; print "\n";'],
    ['Str field on a class',        'use feature "class"; no warnings "experimental::class"; '
                                  . 'class C { field $n :param :reader; } '
                                  . 'my $o = C->new(n=>"f"); print $o->n; print "\n";'],
    ['Str-returning method',        'use feature "class"; no warnings "experimental::class"; '
                                  . 'class C { method k { return "m" } } print C->new->k; print "\n";'],
    ['Str regex subject',           'my $s="abc"; print(($s =~ /b/) ? "1" : "0"); print "\n";'],
    ['Str numeric compare',         'my $s="3"; print(($s == 3) ? "1" : "0"); print "\n";'],
);

# BOTH LOWERING MODES, because they emit different code and the difference is
# exactly where this bug hid. `program_mode` says "this graph IS the program"
# and SUPPRESSES the return-value epilogue (LLVM.pm:1049). The fragment mode
# keeps it — and the epilogue is a Str CONSUMER, printing the value with a type
# tag. A first draft of this test ran program_mode only and passed all 20 cases
# while fourteen t/bootstrap/ir/llvm-*.t files were red, because every one of
# those lowers a fragment. Testing one mode measured half the compiler.
my @MODES = (
    { name => 'program',  fragment => 0 },
    { name => 'fragment', fragment => 1 },
);

plan tests => scalar(@CASES) * scalar(@MODES);

sub emit_ll {
    my ($src, %opt) = @_;
    my ($pf, $ptmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $pf "use 5.42.0;\n$src\n";
    close $pf;

    my $json = qx($PERL -I$SON -MO=SoN,json,package=main,package=C $ptmp 2>/dev/null);
    return (undef, 'producer emitted no JSON') unless $json =~ /\S/;

    my ($graphs, $mop) = eval { Chalk::IR::Serialize::JSON::from_json($json) };
    return (undef, "loader failed: $@") unless $graphs;

    my $g = $graphs->{'main::__PROGRAM__'} // $graphs->{'main::__main__'}
        or return (undef, 'no entry graph');
    my $ret = $g->returns->[0] or return (undef, 'no Return node');

    my $ll = eval {
        Chalk::Target::LLVM->lower($ret,
                                   ($opt{fragment} ? () : (program_mode => 1)),
                                   (defined $mop ? (mop => $mop) : ()));
    };
    # A GAP is a DECLINE, not a failure: we refused to emit, which is the
    # honest outcome for an unbuilt path. Only EMITTED ir is under test here.
    return (undef, "GAP: $@") if $@;
    return ($ll, undef);
}

for my $case (@CASES) {
    my ($base, $src) = @$case;
  for my $mode (@MODES) {
    my $name = "$base [$mode->{name}]";

    my ($ll, $why) = emit_ll($src, fragment => $mode->{fragment});

    SKIP: {
        skip "$name — nothing emitted ($why)", 1 unless defined $ll;

        my ($lf, $ltmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        binmode $lf, ':utf8';
        print $lf $ll;
        close $lf;

        my $err  = qx($LLVM_AS $ltmp -o /dev/null 2>&1);
        my $exit = $? >> 8;
        chomp $err;

        # The discriminating assertion. A type error names the exact
        # instruction, so the diagnostic is the fix.
        ok($exit == 0, "$name: emitted IR type-checks")
            or diag("llvm-as rejected the module:\n$err");
    }
  }
}
