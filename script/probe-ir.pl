# ABOUTME: Audit tool — parses a Perl source snippet and prints MOP::Method->body vs ->graph shapes.
# ABOUTME: Used for the IR completeness audit; not a production script.
use 5.42.0;
use utf8;
use lib 'lib';
use lib 't/bootstrap/lib';
use Scalar::Util qw(blessed refaddr);

use Chalk::MOP;
use Chalk::Bootstrap::Semiring::SemanticAction;
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::BNF::Target::Perl;

# Build grammar once
my $raw = perl_pipeline();
my $bnf = Chalk::Bootstrap::BNF::Target::Perl->new->generate($raw);
my $pkg = 'Chalk::Grammar::IRProbe::' . int(rand(1_000_000));
$bnf =~ s/Chalk::Grammar::BNF::Generated/$pkg/g;
eval $bnf;
die "grammar eval failed: $@" if $@;

my $gen_grammar = do { no strict 'refs'; &{"${pkg}::grammar"}(); };

sub probe($label, $source) {
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    $parser->semiring->reset_cache;
    my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
    my $r;
    eval { $r = $parser->parse_value($source); };
    if ($@) {
        say "== $label";
        say "PARSE ERROR: $@";
        say "";
        return;
    }
    if (!defined $r) {
        say "== $label";
        say "PARSE: returned undef (no IR)";
        say "";
        return;
    }
    if ($r->is_zero) {
        say "== $label";
        say "PARSE: zero (rejected by semiring)";
        say "";
        return;
    }

    say "== $label";
    my @classes = grep { $_->name ne 'main' } $mop->classes;
    my $main = $mop->for_class('main');
    my @main_subs = $main ? $main->subs : ();

    if (!@classes && !@main_subs) {
        say "  no classes, no top-level subs (top-level statements only)";
        say "";
        return;
    }

    for my $cls (@classes) {
        say "  class ", $cls->name;
        for my $m ($cls->methods) {
            _dump_callable("method " . $m->name, $m);
        }
        for my $s ($cls->subs) {
            _dump_callable("sub " . $s->name, $s);
        }
    }
    for my $s (@main_subs) {
        _dump_callable("top-level sub " . $s->name, $s);
    }
    say "";
}

sub _dump_callable($label, $obj) {
    say "    $label";
    my @body = $obj->body->@*;
    say "      body: ", scalar @body, " items";
    for my $i (0..$#body) {
        my $n = $body[$i];
        my $op = ref($n)
            ? ($n->can('operation') ? $n->operation : ref $n)
            : "<scalar:" . (defined $n ? $n : '<undef>') . ">";
        my $extra = '';
        if (blessed $n && $n->can('name') && $n->isa('Chalk::IR::Node::Call')) {
            $extra = " name=" . $n->name;
        }
        say "        [$i] $op$extra";
    }
    my @nodes = $obj->graph->nodes->@*;
    my %ops;
    $ops{$_->operation}++ for @nodes;
    say "      graph: ", scalar @nodes, " nodes -- ",
        join(", ", map { "$_=$ops{$_}" } sort keys %ops);

    # Cross-check: each body item is in graph?
    my %addrs = map { refaddr($_) => 1 } @nodes;
    my @missing = grep { ref $_ && !$addrs{refaddr($_)} } @body;
    if (@missing) {
        say "      WARN: ", scalar @missing, " body item(s) NOT in graph:";
        for my $m (@missing) {
            my $op = $m->can('operation') ? $m->operation : ref $m;
            say "        $op";
        }
    }

    # ANY-inputs reachability from Return: even if a node is in the graph,
    # it must be reachable from a terminator (Return/Unwind) by walking
    # inputs() in any direction, or it's dead from codegen's perspective.
    my @terminators = grep { $_->operation =~ /^(Return|Unwind)$/ } @nodes;
    if (@terminators) {
        my %reached;
        my @work = @terminators;
        while (my $n = shift @work) {
            next unless blessed $n;
            next if $reached{refaddr($n)}++;
            my $ins = $n->inputs // [];
            for my $in ($ins->@*) {
                next unless defined $in;
                if (ref($in) eq 'ARRAY') { push @work, $in->@* }
                else { push @work, $in }
            }
        }
        # Which body items are unreachable?
        my @body_unreach = grep {
            ref $_ && $addrs{refaddr($_)} && !$reached{refaddr($_)}
        } @body;
        if (@body_unreach) {
            say "      WARN: ", scalar @body_unreach, " body item(s) in graph but UNREACHABLE from terminators:";
            for my $m (@body_unreach) {
                my $op = $m->can('operation') ? $m->operation : ref $m;
                my $extra = '';
                if (blessed $m && $m->can('name') && $m->isa('Chalk::IR::Node::Call')) {
                    $extra = " name=" . $m->name;
                }
                say "        $op$extra";
            }
        }
    }
}

# Read source from argv or STDIN
my $source;
if (@ARGV) {
    my $file = shift @ARGV;
    open my $fh, '<:utf8', $file or die "can't open $file: $!";
    local $/;
    $source = <$fh>;
} else {
    local $/;
    $source = <STDIN>;
}

# Multi-snippet input: separator is a line "=== LABEL ==="
my @snippets;
my $cur_label;
my @cur_lines;
for my $line (split /\n/, $source) {
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
if (!@snippets) {
    push @snippets, ['stdin', $source];
}

for my $s (@snippets) {
    probe($s->[0], $s->[1]);
}
