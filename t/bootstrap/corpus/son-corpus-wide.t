# ABOUTME: Phase 4 gate measurement: run EVERY mdtest corpus case through B::SoN.
# ABOUTME: Triple contract per case: behavior (lli == perl) + shape (ir-block subset) + TypedInvariant.
use 5.42.0;
use utf8;
use Test::More;
use JSON::PP;
use File::Temp qw(tempfile);

use lib 'lib', 't/lib';
use Chalk::IR::Serialize::JSON ();
use Chalk::IR::Graph::TypedInvariant;
use Chalk::Target::LLVM;
use Chalk::CodeGen::Harness::TypeTag;
use Chalk::CodeGen::Harness::MdtestCorpus;

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI"        unless -x $LLI;
plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;

# host.md H3 ($ENV{CHALK_G7_TEST}) declares its env dependency in the case
# prose: both the perl oracle and lli inherit this runner's environment (they
# are qx() child processes). Set it so H3 gate-greens here as it does in the
# dedicated host.t runner (which sets the same var).
local $ENV{CHALK_G7_TEST} = 'hostval';

# ---------------------------------------------------------------------------
# The B::SoN pipeline (class-aware), reused shape from son-e2e.t.
# ---------------------------------------------------------------------------
sub split_class_source ($clean) {
    my @lines = split /\n/, $clean;
    my (@head, @driver, @class_names);
    my ($depth, $in_class) = (0, 0);
    for my $line (@lines) {
        if (!$in_class && $line =~ /^\s*(?:use|no)\s+/) { push @head, $line; next; }
        if (!$in_class && $line =~ /^\s*class\s+(\w[\w:]*)/) {
            push @class_names, $1; $in_class = 1; $depth = 0;
        }
        if ($in_class) {
            push @head, $line;
            $depth += ($line =~ tr/{//);
            $depth -= ($line =~ tr/}//);
            $in_class = 0 if $depth <= 0;
            next;
        }
        push @driver, $line;
    }
    my $prog = join("\n", @head) . "\npackage main;\n"
             . "sub corpus_case {\n" . join("\n", @driver) . "\n}\n";
    return ($prog, \@class_names);
}

sub run_through_bson ($source) {
    (my $clean = $source) =~ s/^\s*#[^\n]*\n//gm;
    $clean =~ s/\s+$//;
    my ($prog, $class_names) = split_class_source($clean);
    my $pkg_opts = join(',', 'package=main', map { "package=$_" } @$class_names);

    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $prog;
    close $fh;

    my $json = qx($PERL -I$SON -MO=SoN,json,$pkg_opts $tmp 2>/dev/null);
    return (undef, "B::SoN produced no JSON")        unless $json =~ /\S/;
    my $data = eval { JSON::PP->new->decode($json) };
    return (undef, "JSON decode failed")             unless $data;
    return (undef, "no main::corpus_case method")
        unless $data->{methods}{'main::corpus_case'};

    my ($graphs, $mop) = eval { Chalk::IR::Serialize::JSON::from_json($json) };
    return (undef, "from_json failed: $@")           unless $graphs;
    my $g = $graphs->{'main::corpus_case'} or return (undef, "no loaded graph");
    my $ret = $g->returns->[0] or return (undef, "no Return node", $g);

    my $ll = eval { Chalk::Target::LLVM->lower($ret, (defined $mop ? (mop => $mop) : ())) };
    return (undef, "lower: $@", $g) if $@;

    my ($lfh, $lltmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lfh $ll; close $lfh;
    my $out = qx($LLI $lltmp 2>&1);
    if (my $sig = $? & 127) {
        return (undef, "lli died on signal $sig", $g);
    }
    my $exit = $? >> 8;
    return (undef, "lli exited $exit", $g) if $exit != 0;
    chomp $out;
    return ($out, undef, $g);
}

sub perl_oracle ($source) {
    (my $clean = $source) =~ s/^\s*#[^\n]*\n//gm;
    $clean =~ s/\s+$//;
    my $frag = Chalk::CodeGen::Harness::TypeTag::oracle_perl_fragment();
    my $prog = "use 5.42.0;\nuse utf8;\nmy \$_result = do {\n$clean\n};\n$frag";
    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $prog; close $fh;
    my $out = qx($PERL $tmp 2>&1);
    chomp $out;
    return $out;
}

# ---------------------------------------------------------------------------
# Iterate every case in every topic file.
# ---------------------------------------------------------------------------
my @topics = sort glob('t/corpus/mdtest/*.md');

my %tally = (green => 0, gap_declared => 0, bug => 0, no_source => 0,
             shape_ok => 0, inv_ok => 0, gate_green => 0);
my %by_topic;
my @bugs;

for my $md (@topics) {
    my $topic = $md =~ m{/([^/]+)\.md$} ? $1 : $md;
    my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($md);

    for my $case (@$cases) {
        my $title  = $case->{title} // '?';
        my $source = $case->{source};
        my $label  = "$topic: $title";

        unless (defined $source && $source =~ /\S/) {
            $tally{no_source}++;
            next;   # section with no perl block (prose)
        }

        my $verdict = Chalk::CodeGen::Harness::MdtestCorpus
            ->parse_l_verdict_from_ir($case->{ir} // '');

        # Corpus-declared GAP: not expected to lower; record honestly.
        if ($verdict eq 'GAP') {
            $tally{gap_declared}++;
            $by_topic{$topic}{gap}++;
            pass("$label: corpus-declared GAP (skipped)");
            next;
        }

        my $oracle = perl_oracle($source);
        my ($lli, $err, $g) = run_through_bson($source);

        # The triple contract (Phase 4 gate): behavior AND shape AND invariant.
        my $behavior_ok = defined $lli && $lli eq $oracle;

        my ($shape_ok, $shape_why) = (0, 'no loaded graph');
        my ($inv_ok,   $inv_why)   = (0, 'no loaded graph');
        if (defined $g) {
            # Each leg is exception-isolated: a die in one graph walk must
            # cost that case only, not abort the whole gap map.
            my $shape = eval {
                Chalk::CodeGen::Harness::MdtestCorpus
                    ->shape_subset_check($case->{ir}, $g->returns->[0]);
            } // { verdict => 'FAIL', missing => [], reason => "died: $@" };
            $shape_ok  = $shape->{verdict} eq 'PASS';
            $shape_why = $shape->{verdict} eq 'FAIL' && $shape->{missing}->@*
                ? 'missing [' . join(', ', $shape->{missing}->@*) . ']'
                : ($shape->{reason} // '');

            my $inv = eval { Chalk::IR::Graph::TypedInvariant->check($g->nodes) }
                // { ok => 0, violations => [{ message => "died: $@" }] };
            $inv_ok  = $inv->{ok} ? 1 : 0;
            $inv_why = $inv->{ok} ? ''
                : join('; ', map { $_->{message} } $inv->{violations}->@*);
        }

        $tally{green}++,      $by_topic{$topic}{green}++      if $behavior_ok;
        $tally{shape_ok}++,   $by_topic{$topic}{shape}++      if $shape_ok;
        $tally{inv_ok}++,     $by_topic{$topic}{inv}++        if $inv_ok;

        if ($behavior_ok && $shape_ok && $inv_ok) {
            $tally{gate_green}++;
            $by_topic{$topic}{gate}++;
            pass("$label: gate-green (behavior + shape + invariant)");
        }
        else {
            my @why;
            push @why, (defined $lli ? "lli '$lli' != perl '$oracle'" : $err)
                unless $behavior_ok;
            push @why, "shape: $shape_why"     unless $shape_ok;
            push @why, "invariant: $inv_why"   unless $inv_ok;
            my $why = join(' | ', @why);
            $tally{bug}++;
            $by_topic{$topic}{bug}++;
            push @bugs, "$label -> $why";
            # Not a test failure: this is the gap map. Mark TODO so red = worklist.
            TODO: {
                local $TODO = "B::SoN gap (worklist, not a regression)";
                fail("$label: $why");
            }
        }
    }
}

# ---------------------------------------------------------------------------
# The map.
# ---------------------------------------------------------------------------
diag("");
diag("=== Phase 4 corpus-wide status (triple contract: behavior+shape+invariant) ===");
for my $t (sort keys %by_topic) {
    my $b = $by_topic{$t};
    diag(sprintf("  %-14s gate=%-2d behavior=%-2d shape=%-2d inv=%-2d gap=%-2d worklist=%-2d",
        $t, $b->{gate} // 0, $b->{green} // 0, $b->{shape} // 0,
        $b->{inv} // 0, $b->{gap} // 0, $b->{bug} // 0));
}
diag("");
diag(sprintf(
    "TOTAL: gate-green=%d  behavior=%d  shape=%d  invariant=%d  gap-declared=%d  worklist=%d  (no-source sections=%d)",
    @tally{qw(gate_green green shape_ok inv_ok gap_declared bug no_source)}));
if (@bugs) {
    diag("");
    diag("=== worklist (triple-contract gaps to close) ===");
    diag("  $_") for @bugs;
}

# The gate floor: the worklist is TODO (red = worklist, not regression), but
# already-certified gate-green cases must never silently regress. Raise the
# floor as the shape-contract families (019f2a50 pair) land.
cmp_ok($tally{gate_green}, '>=', 50, 'gate-green floor (50 after EnvRead producer, host H3)');

done_testing();
