# ABOUTME: I11 Mode-2 tri-fold adapter — runs harvested cases (behavior+invariant,
# ABOUTME: contract C) under a SEPARATE conformance tally, plus a promote-to-hand path.
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

use File::Temp ();
use JSON::PP;

use Chalk::IR::Serialize::JSON ();
use Chalk::IR::Graph::TypedInvariant;
use Chalk::Target::LLVM;
use Chalk::CodeGen::Harness::TypeTag;

# Wrap each harvested Mode-2 case (I10 extractor output) into a tri-fold runner.
#
# SHAPE-LEG CONTRACT C (the key design point): a HARVESTED case has no
# hand-written ir block, so it runs BEHAVIOR + INVARIANT only — NOT the
# hand-corpus ir-block shape check. The full tri-fold (behavior + shape +
# invariant) belongs to the HAND corpus alone.
#
# BEHAVIOR: the harvested EXPECTED is the oracle — Perl's t/ already told us the
# answer, so we DO NOT re-run perl. We lower `<preamble>; <subject>` under lli
# and compare the lli result to the type-tagged harvested expected.
#
# HONEST-NUMBER DISCIPLINE (R6.1): the harvested-conformance tally is SEPARATE
# from hand-corpus gate-green. This module NEVER touches the hand corpus; it only
# reports how many harvestable cases lower to their expected value. A case that
# reveals a real gap is a candidate for PROMOTION into the hand corpus with an ir
# block — promote() emits the hand-corpus-shaped record for that.
class Chalk::CodeGen::Harness::Mode2Adapter {

    my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
    my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
    my $LLI  = '/usr/lib/llvm-15/bin/lli';

    # run_cases(\@cases) -> {
    #   conformance => { pass, total, pct },   # SEPARATE harvested tally
    #   cases       => [ { subject, behavior_ok, invariant_ok, lli, expected, err } ],
    #   promotions  => [ <hand-corpus record>, ... ],   # gap-revealing candidates
    # }
    #
    # Contract C: each case runs BEHAVIOR + INVARIANT only. No shape leg — a
    # harvested case has no hand ir block, so a verdict never carries shape_ok.
    sub run_cases ($class, $cases) {
        my (@verdicts, @promotions);
        my ($pass, $total) = (0, 0);

        for my $case ($cases->@*) {
            $total++;
            my $v = $class->_run_one($case);
            push @verdicts, $v;

            $pass++ if $v->{behavior_ok} && $v->{invariant_ok};

            # A case that lowers wrong / GAPs is a promotion candidate: it reveals
            # a real gap the hand corpus should certify with a full tri-fold ir
            # block. Behavior-conforming cases are already covered by the tally.
            unless ($v->{behavior_ok} && $v->{invariant_ok}) {
                push @promotions, $class->promote($case);
            }
        }

        my $pct = $total ? int(0.5 + 100 * $pass / $total) : 0;
        return {
            conformance => { pass => $pass, total => $total, pct => $pct },
            cases       => \@verdicts,
            promotions  => \@promotions,
        };
    }

    # _run_one($case) -> { subject, expected, behavior_ok, invariant_ok, lli, err }
    #
    # BEHAVIOR: lower `<preamble>; <subject>` and compare the lli result to the
    # type-tagged harvested expected (the oracle). INVARIANT: TypedInvariant over
    # the loaded graph. NO shape leg (contract C).
    sub _run_one ($class, $case) {
        my $expected_tag = _tag_expected($case);
        my ($lli, $err, $g) = _lower_case($case);

        my $behavior_ok  = defined $lli && $lli eq $expected_tag;
        my ($invariant_ok, $inv_why) = (0, 'no loaded graph');
        if (defined $g) {
            my $inv = eval { Chalk::IR::Graph::TypedInvariant->check($g->nodes) }
                // { ok => 0, violations => [{ message => "died: $@" }] };
            $invariant_ok = $inv->{ok} ? 1 : 0;
            $inv_why = $inv->{ok} ? ''
                : join('; ', map { $_->{message} } $inv->{violations}->@*);
        }

        return {
            subject      => $case->{subject},
            expected     => $expected_tag,
            behavior_ok  => $behavior_ok,
            invariant_ok => $invariant_ok,
            lli          => $lli,
            err          => $err,
            inv_why      => $inv_why,
        };
    }

    # promote($case) -> hand-corpus-shaped record for a gap-revealing case.
    #
    # A harvested case that reveals a real gap is a candidate for PROMOTION into
    # the hand corpus WITH an ir block (full tri-fold). This emits the record a
    # human fills in: source (the case body), behavior (the harvested expected as
    # the return value), and an ir block STAMPED `L: GAP` — the ir shape is what a
    # human must author and re-certify to make the case a full tri-fold GREEN. The
    # GAP stamp is honest: until a human writes the ir block, the case is not
    # certified.
    sub promote ($class, $case) {
        my $body = _case_body($case);
        return {
            source   => $body,
            behavior => "return: $case->{expected}\ncontext: scalar",
            # The ir block is a human-authored artifact; we stamp it GAP so it is
            # never mistaken for a certified case. `%TODO` marks the hole.
            ir       => "%TODO = <author the ir shape for `$body`>\n"
                      . "return %TODO\nL: GAP",
            origin   => { file => $case->{file}, line => $case->{line} },
        };
    }

    # --- pipeline (cloned shape from son-corpus-wide.t run_through_bson) ------

    # _lower_case($case) -> ($lli_stdout, $err, $graph)
    # Build `sub corpus_case { <preamble>; <subject> }`, run through B::SoN +
    # Target::LLVM + lli. On any failure returns (undef, $reason, $graph_or_undef).
    sub _lower_case ($case) {
        my $body = _case_body($case);
        my $prog = "use 5.42.0;\nuse utf8;\npackage main;\n"
                 . "sub corpus_case {\n$body\n}\n";

        my ($fh, $tmp) = File::Temp::tempfile(SUFFIX => '.pl', UNLINK => 1);
        binmode $fh, ':utf8';
        print $fh $prog;
        close $fh;

        my $json = qx($PERL -I$SON -MO=SoN,json,package=main $tmp 2>/dev/null);
        return (undef, "B::SoN produced no JSON", undef) unless $json =~ /\S/;

        my $data = eval { JSON::PP->new->decode($json) };
        return (undef, "JSON decode failed", undef) unless $data;
        return (undef, "no main::corpus_case method", undef)
            unless $data->{methods}{'main::corpus_case'};

        my ($graphs, $mop) = eval { Chalk::IR::Serialize::JSON::from_json($json) };
        return (undef, "from_json failed: $@", undef) unless $graphs;
        my $g = $graphs->{'main::corpus_case'}
            or return (undef, "no loaded graph", undef);
        my $ret = $g->returns->[0]
            or return (undef, "no Return node", $g);

        my $ll = eval { Chalk::Target::LLVM->lower($ret, (defined $mop ? (mop => $mop) : ())) };
        return (undef, "lower: $@", $g) if $@;

        my ($lfh, $lltmp) = File::Temp::tempfile(SUFFIX => '.ll', UNLINK => 1);
        binmode $lfh, ':utf8';
        print $lfh $ll;
        close $lfh;
        my $out = qx($LLI $lltmp 2>&1);
        if (my $sig = $? & 127) {
            return (undef, "lli died on signal $sig", $g);
        }
        my $exit = $? >> 8;
        return (undef, "lli exited $exit", $g) if $exit != 0;
        chomp $out;
        return ($out, undef, $g);
    }

    # --- helpers -------------------------------------------------------------

    # _case_body($case) -> "<preamble lines>\n<subject>"
    # A harvested case may carry a self-contained `my $x = <literal>;` preamble
    # (I10 R5.2) the subject references; the body is the preamble followed by the
    # subject expression as the block's value.
    sub _case_body ($case) {
        my @pre = ($case->{preamble} // [])->@*;
        return join("\n", @pre, $case->{subject});
    }

    # _tag_expected($case) -> the harvested expected, type-tagged to match the
    # lli epilogue face. The harvested expected is a plain literal (e.g. 4 or '-')
    # and lli prints `Int:4` / `Str:-`; infer_tag is the declared-value oracle
    # (TypeTag) that turns a plain literal into its tagged face.
    sub _tag_expected ($case) {
        return Chalk::CodeGen::Harness::TypeTag::infer_tag($case->{expected});
    }
}
