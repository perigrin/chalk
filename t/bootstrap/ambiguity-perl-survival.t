# ABOUTME: Red test — asserts Boolean::add ambiguous wrappers survive into the Perl-grammar parse tree.
# ABOUTME: Currently failing (0 wrappers reachable from 40 created). Defines success for wrapper-loss investigation.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_recognizer);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Semiring::Boolean;

use Scalar::Util qw(blessed refaddr);

# Build the Perl grammar recognizer once.
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();
BAIL_OUT('Perl grammar failed to parse') unless defined $ir;

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::AmbSurvival/g;
eval $generated;
BAIL_OUT("Generated code failed to compile: $@") if $@;

my $gen_grammar = Chalk::Grammar::Perl::AmbSurvival::grammar();
my $rec = build_perl_recognizer($gen_grammar, start => 'Program');
BAIL_OUT('Recognizer not built') unless defined $rec;

# Record every ambiguous wrapper Boolean::add creates.
our %created_wrappers;
my $orig_add = \&Chalk::Bootstrap::Semiring::Boolean::add;
no warnings 'redefine';
*Chalk::Bootstrap::Semiring::Boolean::add = sub {
    my ($self, $left, $right) = @_;
    my $result = $orig_add->($self, $left, $right);
    if (blessed($result)
        && $result->isa('Chalk::Bootstrap::Context')
        && $result->annotations->{ambiguous}) {
        $created_wrappers{refaddr($result)} = 1;
    }
    return $result;
};

# For each test input: verify that at least one of the ambiguous wrappers
# created during parsing is reachable from the returned Context tree.
#
# If add() creates wrappers but none are reachable, the wrappers are being
# discarded somewhere between creation and return — the wrapper-loss bug
# that blocks the ambiguity corpus.
sub count_reachable_wrappers($root) {
    return 0 unless blessed($root) && $root->isa('Chalk::Bootstrap::Context');
    my %seen;
    my @queue = ($root);
    while (@queue) {
        my $n = shift @queue;
        next unless blessed($n) && $n->isa('Chalk::Bootstrap::Context');
        next if $seen{refaddr($n)}++;
        push @queue, $n->children->@*;
    }
    my $reachable = 0;
    for my $addr (keys %created_wrappers) {
        $reachable++ if $seen{$addr};
    }
    return $reachable;
}

# Test cases — each is known to trigger Boolean::add calls during parse.
# The exact counts have been observed empirically; they may shift as the
# grammar evolves. What must not shift is that SOME wrappers remain
# reachable when wrappers are created.
my @cases = (
    ['42;',         1],
    ['1 + 2;',     20],
    ['1 + 2 * 3;', 40],
);

TODO: {
    local $TODO = 'wrapper-loss bug: wrappers created by Boolean::add are not '
                . 'reachable from returned Context; see '
                . 'docs/plans/2026-04-23-earley-reification-overwrites-add-merge-design.md '
                . 'and docs/plans/2026-04-24-option-b-grammar-refactor-postmortem.md';

    for my $case (@cases) {
        my ($input, $min_merges) = @$case;
        %created_wrappers = ();
        my $ctx = $rec->parse_value($input);
        ok(defined $ctx, "parses '$input'");
        next unless defined $ctx;

        my $created  = scalar keys %created_wrappers;
        my $reachable = count_reachable_wrappers($ctx);

        cmp_ok($created, '>=', $min_merges,
            "'$input': at least $min_merges Boolean::add wrappers created (got $created)");

        cmp_ok($reachable, '>', 0,
            "'$input': at least one ambiguous wrapper survives into returned tree "
            . "(got $reachable of $created reachable)");
    }
}

done_testing();
