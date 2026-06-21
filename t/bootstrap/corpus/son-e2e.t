# ABOUTME: Phase 4b-3 end-to-end runner: corpus source -> B::SoN -> JSON -> Chalk -> lli == perl.
# ABOUTME: Validates the producible-now slice through the real producer (not the IR-block builder).
use 5.42.0;
use utf8;
use Test::More;
use JSON::PP;
use File::Temp qw(tempfile);

use lib 'lib', 't/lib';
use Chalk::IR::Serialize::JSON ();
use Chalk::Target::LLVM;
use Chalk::CodeGen::Harness::TypeTag;

# ---------------------------------------------------------------------------
# Environment gates
# ---------------------------------------------------------------------------
my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI"        unless -x $LLI;
plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;

# ---------------------------------------------------------------------------
# Pipeline: corpus source string -> (lli_output, error)
#
# The corpus source is a top-level program (last expression is the value), so
# it is wrapped as a sub for B::SoN (which translates CVs). The sub's Return
# carries the last expression's value, matching the perl oracle's do { ... }.
# ---------------------------------------------------------------------------
sub run_through_bson ($source) {
    # Wrap as a named sub in package main.
    (my $clean = $source) =~ s/^\s*#[^\n]*\n//gm;
    $clean =~ s/\s+$//;
    my $prog = "package main;\nsub corpus_case {\n$clean\n}\n";

    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $prog;
    close $fh;

    my $json = qx($PERL -I$SON -MO=SoN,json,package=main $tmp 2>/dev/null);
    return (undef, "B::SoN produced no JSON") unless $json =~ /\S/;

    my $data = eval { JSON::PP->new->decode($json) };
    return (undef, "JSON decode failed: $@") unless $data;

    my $m = $data->{methods}{'main::corpus_case'};
    return (undef, "no main::corpus_case method") unless $m;

    my $filtered = {
        version => 1, source => 'corpus',
        methods => { 'main::corpus_case' => $m },
    };

    my $graphs = eval {
        Chalk::IR::Serialize::JSON::from_json(JSON::PP->new->encode($filtered));
    };
    return (undef, "from_json failed: $@") unless $graphs;

    my $g = $graphs->{'main::corpus_case'};
    return (undef, "no loaded graph") unless $g;

    my $ret = $g->returns->[0];
    return (undef, "no Return node") unless $ret;

    my $ll = eval { Chalk::Target::LLVM->lower($ret) };
    return (undef, "LLVM lowering GAP: $@") if $@;

    # Run the emitted IR through lli.
    my ($lfh, $lltmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lfh $ll;
    close $lfh;
    my $out = qx($LLI $lltmp 2>&1);
    my $exit = $? >> 8;
    return (undef, "lli exited $exit: $out") if $exit != 0;
    chomp $out;
    return ($out, undef);
}

# Perl oracle: type-tagged canonical value (same tagging as the corpus harness).
sub perl_oracle ($source) {
    (my $clean = $source) =~ s/^\s*#[^\n]*\n//gm;
    $clean =~ s/\s+$//;
    my $frag = Chalk::CodeGen::Harness::TypeTag::oracle_perl_fragment();
    my $prog = "use 5.42.0;\nuse utf8;\nmy \$_result = do {\n$clean\n};\n$frag";
    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $prog;
    close $fh;
    my $out = qx($PERL $tmp 2>&1);
    chomp $out;
    return $out;
}

# ---------------------------------------------------------------------------
# The producible-now slice (4a gap map). Each case: a corpus source and whether
# we expect it to reach lli (GREEN) or to be an honest GAP at this stage.
# Cases are tagged so a GAP is recorded explicitly, never silently passed.
# ---------------------------------------------------------------------------
my @slice = (
    # arithmetic (perl constant-folds these to a single Constant)
    { topic => 'arithmetic', src => '1 + 2',  expect => 'green' },
    { topic => 'arithmetic', src => '5 - 3',  expect => 'green' },
    { topic => 'arithmetic', src => '3 * 4',  expect => 'green' },
    { topic => 'arithmetic', src => '3 / 4',  expect => 'green' },
    { topic => 'arithmetic', src => '-7 % 3', expect => 'green' },
    # statements (literals)
    { topic => 'statements',  src => '5',                 expect => 'green' },
    { topic => 'statements',  src => 'my $x = 1; my $y = 2; $x + $y', expect => 'green' },
    # variables
    { topic => 'variables',   src => 'my $x = 1; $x',     expect => 'green' },
    { topic => 'variables',   src => 'my $x; $x = 1; $x', expect => 'green' },
    { topic => 'variables',   src => 'my $x = 1; $x = 2; $x', expect => 'green' },
    # strings
    { topic => 'strings',     src => q{my $s = 'hello'; $s},     expect => 'green' },
    { topic => 'strings',     src => q{"hello" . " world"},      expect => 'green' },

    # Constant-folded comparisons: B::SoN recovers PL_sv_yes/PL_sv_no as a
    # Boolean Constant (4b-3b), and the LLVM backend lowers a Bool constant to
    # i1, so these now reach lli == perl (Bool:1 / Bool:).
    { topic => 'statements',  src => '1 < 2', expect => 'green' },
    { topic => 'statements',  src => '2 < 1', expect => 'green' },

    # references R6/R7: array/hash element assignment. Under canonical ops
    # (4b-4) these are array-build (aassign -> ArrayRef) + element store
    # (aelem/helem lvalue + sassign -> Assign over Subscript) + element read.
    { topic => 'references', src => 'my @a = (1, 2, 3); $a[0] = 42; $a[0]', expect => 'green' },
    { topic => 'references', src => 'my %h = (k => 0); $h{k} = 99; $h{k}',  expect => 'green' },

    # variables C2: numeric compound assignment (`$x += 2`). Under canonical ops
    # (4b-5) this is a read-modify-write: the add over an lvalue $x rebinds $x.
    { topic => 'variables', src => 'my $x = 1; $x += 2; $x', expect => 'green' },

    # increment K1/K2: ++$i / $i++ are read-modify-write (preinc/predec ops,
    # NOT TARGMY). 4b-6 lowers them to Add/Subtract($i, 1) + rebind; both corpus
    # cases read $i after, so both expect 1.
    { topic => 'increment', src => 'my $i = 0; ++$i; $i', expect => 'green' },
    { topic => 'increment', src => 'my $i = 0; $i++; $i', expect => 'green' },

    # strings S4 (`$s .= 'b'`): a multiconcat with APPEND|TARGMY. 4b-4b handles
    # the TARGMY store-back (write result to the targ slot + rebind).
    { topic => 'strings', src => q{my $s = 'a'; $s .= 'b'; $s}, expect => 'green' },

    # scalar self-assign (`$x = $x + 1`): an add with TARGMY (OPpTARGET_MY),
    # writing its result in-place to the pad slot. 4b-4b rebinds the targ.
    { topic => 'variables', src => 'my $x = 5; $x = $x + 1; $x', expect => 'green' },
);

my %tally = (green => 0, gap => 0, bug => 0);

for my $case (@slice) {
    my $label = "$case->{topic}: $case->{src}";
    subtest $label => sub {
        my $oracle = perl_oracle($case->{src});
        ok(defined $oracle && length $oracle, "perl oracle produced a value ($oracle)");

        my ($lli, $err) = run_through_bson($case->{src});

        if ($case->{expect} eq 'green') {
            if (defined $lli) {
                is($lli, $oracle, "lli '$lli' == perl oracle '$oracle'")
                    and $tally{green}++;
            }
            else {
                $tally{bug}++;
                fail("expected GREEN but pipeline failed: $err");
                diag("NEWLY-LOCALIZED PRODUCER/SEAM BUG: $label -> $err");
            }
        }
        else {
            # Declared GAP: record it honestly, do not assert lli==perl.
            $tally{gap}++;
            ok(1, "declared GAP (recorded, not silently passed): " . ($err // 'no error'));
            diag("GAP: $label" . (defined $err ? " -> $err" : ''));
        }
    };
}

diag("=== 4b-3 producible-now slice tally ===");
diag("GREEN (lli==perl): $tally{green}");
diag("GAP   (honest):    $tally{gap}");
diag("BUG   (localized): $tally{bug}");

done_testing();
