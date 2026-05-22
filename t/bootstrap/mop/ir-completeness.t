# ABOUTME: Asserts every body item in MOP::Method is in graph AND reachable from a terminator.
# ABOUTME: Phase 3d TDD red — covers the 56-snippet corpus identified by 2026-05-22 IR audit.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed refaddr);
use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::Bootstrap::Semiring::SemanticAction;
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::BNF::Target::Perl;

# Build grammar once, share across all snippets.
my $raw = perl_pipeline();
my $bnf = Chalk::Bootstrap::BNF::Target::Perl->new->generate($raw);
my $pkg = 'Chalk::Grammar::Perl::IRCompletenessTest';
$bnf =~ s/Chalk::Grammar::BNF::Generated/$pkg/g;
eval $bnf;
BAIL_OUT("grammar eval: $@") if $@;
my $gen_grammar = do { no strict 'refs'; &{"${pkg}::grammar"}(); };

# Load the audit corpus.
my $corpus_path = 't/fixtures/ir-audit-corpus.pl';
open my $cfh, '<:utf8', $corpus_path or BAIL_OUT("cannot read $corpus_path: $!");
local $/;
my $corpus = <$cfh>;
close $cfh;

# Split corpus on `=== LABEL` markers.
my @snippets;
my $cur_label;
my @cur_lines;
for my $line (split /\n/, $corpus) {
    if ($line =~ /^===\s*(.+?)\s*(?:===\s*)?$/) {
        if (defined $cur_label) {
            push @snippets, [$cur_label, join("\n", @cur_lines) . "\n"];
        }
        $cur_label = $1;
        @cur_lines = ();
    } else {
        push @cur_lines, $line;
    }
}
if (defined $cur_label) {
    push @snippets, [$cur_label, join("\n", @cur_lines) . "\n"];
}

ok(scalar @snippets > 0, 'corpus loaded') or BAIL_OUT('no snippets');

sub parse_callables($source) {
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    $parser->semiring->reset_cache;
    my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
    my $r;
    eval { $r = $parser->parse_value($source); };
    return () if $@ || !defined $r || $r->is_zero;

    my @callables;
    for my $cls ($mop->classes) {
        next if $cls->name eq 'main';
        for my $m ($cls->methods) {
            push @callables, ['method ' . $cls->name . '::' . $m->name, $m];
        }
        for my $s ($cls->subs) {
            push @callables, ['sub ' . $cls->name . '::' . $s->name, $s];
        }
    }
    my $main = $mop->for_class('main');
    if ($main) {
        for my $s ($main->subs) {
            push @callables, ['top-level sub ' . $s->name, $s];
        }
    }
    return @callables;
}

# Walk inputs() backward from every terminator until fixpoint; return refaddr set of reached nodes.
# Also follows control_in() when the node has one, since control_in carries effect-chain edges
# that live outside the inputs arrayref.
sub reachable_from_terminators(@terminators) {
    my %seen;
    my @work = @terminators;
    while (my $n = shift @work) {
        next unless blessed $n;
        next if $seen{refaddr($n)}++;
        my $ins = $n->inputs // [];
        for my $in ($ins->@*) {
            next unless defined $in;
            if (ref($in) eq 'ARRAY') { push @work, $in->@* }
            else { push @work, $in }
        }
        if ($n->can('control_in')) {
            my $cin = $n->control_in;
            push @work, $cin if defined $cin;
        }
    }
    return \%seen;
}

# Snippets known to expose IR gaps not blocking self-hosting; the
# completeness check is wrapped in TODO so the failures are visible
# without blocking the suite. Each entry should link to a tracked
# issue or follow-on phase.
my %TODO_BY_LABEL = (
    'M7: for-as-foreach (no my)' =>
        'ForeachStatement action drops iterator-less form; no lib/ usage. Tracked: docs/plans/2026-05-22-corpus-alignment-audit.md',
);

for my $entry (@snippets) {
    my ($label, $source) = $entry->@*;
    my @callables = parse_callables($source);

    if (!@callables) {
        fail("$label: parse produced no callables");
        next;
    }

    local our $TODO = $TODO_BY_LABEL{$label};

    for my $callable (@callables) {
        my ($cname, $obj) = $callable->@*;
        my @body  = $obj->body->@*;
        my @nodes = $obj->graph->nodes->@*;
        my %addrs = map { refaddr($_) => 1 } @nodes;
        my @terminators = grep {
            blessed($_) && $_->operation =~ /^(Return|Unwind)$/
        } @nodes;
        my $reached = @terminators
            ? reachable_from_terminators(@terminators)
            : {};

        for my $i (0..$#body) {
            my $item = $body[$i];
            next unless ref $item;  # skip scalars
            next unless blessed $item;  # skip plain hashrefs

            # Metadata structs (e.g., SubInfo from 'my sub' declarations)
            # are not IR nodes and never enter the graph by design. They
            # ride along in body for codegen's benefit; codegen doesn't
            # need them to be graph-resident or terminator-reachable.
            next if $item->isa('Chalk::IR::SubInfo');
            next if $item->isa('Chalk::IR::MethodInfo');
            next if $item->isa('Chalk::IR::FieldInfo');
            next if $item->isa('Chalk::IR::ClassInfo');
            next if $item->isa('Chalk::IR::UseInfo');

            my $op = $item->can('operation')
                ? $item->operation : ref $item;
            my $body_pos = "body[$i] $op";

            ok($addrs{refaddr($item)},
                "[$label] $cname: $body_pos is in graph");

            if ($addrs{refaddr($item)} && @terminators) {
                ok($reached->{refaddr($item)},
                    "[$label] $cname: $body_pos reachable from terminator");
            }
        }
    }
}

done_testing();
