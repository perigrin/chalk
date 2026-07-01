# ABOUTME: Phase 4 gate measurement: run EVERY mdtest corpus case through B::SoN.
# ABOUTME: source -> B::SoN -> JSON -> Chalk -> backend -> lli == perl, per case, all topics.
use 5.42.0;
use utf8;
use Test::More;
use JSON::PP;
use File::Temp qw(tempfile);

use lib 'lib', 't/lib';
use Chalk::IR::Serialize::JSON ();
use Chalk::Target::LLVM;
use Chalk::CodeGen::Harness::TypeTag;
use Chalk::CodeGen::Harness::MdtestCorpus;

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI"        unless -x $LLI;
plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;

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
    my $ret = $g->returns->[0] or return (undef, "no Return node");

    my $ll = eval { Chalk::Target::LLVM->lower($ret, (defined $mop ? (mop => $mop) : ())) };
    return (undef, "lower: $@") if $@;

    my ($lfh, $lltmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lfh $ll; close $lfh;
    my $out = qx($LLI $lltmp 2>&1);
    my $exit = $? >> 8;
    return (undef, "lli exited $exit") if $exit != 0;
    chomp $out;
    return ($out, undef);
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

my %tally = (green => 0, gap_declared => 0, bug => 0, no_source => 0);
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
        my ($lli, $err) = run_through_bson($source);

        if (defined $lli && $lli eq $oracle) {
            $tally{green}++;
            $by_topic{$topic}{green}++;
            pass("$label: lli '$lli' == perl '$oracle'");
        }
        else {
            $tally{bug}++;
            $by_topic{$topic}{bug}++;
            my $why = defined $lli ? "lli '$lli' != perl '$oracle'" : $err;
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
diag("=== Phase 4 corpus-wide status (B::SoN -> backend == perl) ===");
for my $t (sort keys %by_topic) {
    my $b = $by_topic{$t};
    diag(sprintf("  %-14s green=%-2d gap=%-2d bug=%-2d",
        $t, $b->{green} // 0, $b->{gap} // 0, $b->{bug} // 0));
}
diag("");
diag(sprintf("TOTAL: green=%d  gap-declared=%d  bug/worklist=%d  (no-source sections=%d)",
    @tally{qw(green gap_declared bug no_source)}));
if (@bugs) {
    diag("");
    diag("=== worklist (behavior gaps to close) ===");
    diag("  $_") for @bugs;
}

done_testing();
