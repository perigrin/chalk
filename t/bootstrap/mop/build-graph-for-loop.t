# ABOUTME: Phase 3e — C-style for loop ('for (init; cond; incr) BODY') produces a Loop CFG node.
# ABOUTME: Confirms the loop body is in the graph and reachable from the method's Return.
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

my $raw = perl_pipeline();
my $bnf = Chalk::Bootstrap::BNF::Target::Perl->new->generate($raw);
$bnf =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::ForLoopTest/g;
eval $bnf;
BAIL_OUT("grammar: $@") if $@;
my $gen_grammar = Chalk::Grammar::ForLoopTest::grammar();

sub parse_method($source) {
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    $parser->semiring->reset_cache;
    my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
    my $r;
    eval { $r = $parser->parse_value($source); };
    return undef if $@ || !defined $r || $r->is_zero;
    my ($cls) = grep { $_->name ne 'main' } $mop->classes;
    return undef unless $cls;
    return ($cls->methods)[0];
}

sub reachable_from_returns($method) {
    my $graph = $method->graph;
    my @rets = grep { $_->operation =~ /^(Return|Unwind)$/ } $graph->nodes->@*;
    my %seen;
    my @work = @rets;
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

# T1: basic accumulator loop
{
    my $source = q{
class C {
    method m() {
        my $sum = 0;
        for (my $i = 0; $i < 3; $i = $i + 1) {
            $sum = $sum + $i;
        }
        return $sum;
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'T1 parses');
    if ($method) {
        my @nodes = $method->graph->nodes->@*;
        my %ops; $ops{$_->operation}++ for @nodes;
        ok($ops{Loop}, "T1: graph contains a Loop node (got: "
            . join(', ', map { "$_=$ops{$_}" } sort keys %ops) . ')');
        ok($ops{If}, 'T1: graph contains an If node (loop condition)');
        ok($ops{Region}, 'T1: graph contains a Region (post-loop merge)');

        # The accumulator $sum is updated inside the body — there should be
        # a Phi node for it at the Loop header.
        ok($ops{Phi}, 'T1: graph contains a Phi node (loop-carried $sum)');

        my $reached = reachable_from_returns($method);
        my $loop = (grep { $_->operation eq 'Loop' } @nodes)[0];
        ok($reached->{refaddr($loop)},
            'T1: Loop is reachable from Return') if $loop;
    }
}

# T2: increment via += compound assignment
{
    my $source = q{
class C {
    method m() {
        my $sum = 0;
        for (my $i = 0; $i < 4; $i += 2) {
            $sum = $sum + $i;
        }
        return $sum;
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'T2 parses');
    if ($method) {
        my @nodes = $method->graph->nodes->@*;
        my %ops; $ops{$_->operation}++ for @nodes;
        ok($ops{Loop}, 'T2: graph contains a Loop node');
    }
}

# T3: body contains a Call (bare push) — make sure the body is preserved
{
    my $source = q{
class C {
    method m() {
        my @out = ();
        for (my $i = 0; $i < 3; $i = $i + 1) {
            push @out, $i;
        }
        return scalar @out;
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'T3 parses');
    if ($method) {
        my @nodes = $method->graph->nodes->@*;
        my %ops; $ops{$_->operation}++ for @nodes;
        ok($ops{Call}, 'T3: graph contains the Call (push) from the loop body');
    }
}

done_testing();
