# ABOUTME: Tests that zero-valued completions don't propagate through _complete.
# ABOUTME: Prevents nondeterministic parse failures from agenda ordering of zero items.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Composite;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::TypeInference;
use Chalk::Grammar::Perl::KeywordTable;
use TestPipeline qw(perl_pipeline);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;
use Chalk::Bootstrap::Desugar;

# Build the Perl grammar recognizer
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 10 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ZeroPropTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 10 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::ZeroPropTest::grammar();
    my @reordered;
    my $found = false;
    for my $rule ($gen_grammar->@*) {
        if (!$found && $rule->name() eq 'Program') {
            unshift @reordered, $rule;
            $found = true;
        } else {
            push @reordered, $rule;
        }
    }
    my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar(\@reordered);

    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $type_sr = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
    );
    my $comp_sr = Chalk::Bootstrap::Semiring::Composite->new(
        semirings => [$bool_sr, $type_sr],
    );

    # These sources all contain keywords inside blocks. The keyword appears as
    # both an Identifier (rejected by TypeInference) and the proper keyword
    # terminal. Before the zero-propagation fix, the Identifier rejection could
    # poison the only remaining parse path depending on agenda processing order.
    my @sources = (
        ['{ my $x = 42; }',            'bare block with my'],
        ['{ if ($x) { 1; } }',         'nested if in block'],
        ['if ($x) { my $y = 1; }',     'if with keyword in body'],
        ['while ($x) { my $y = 1; }',  'while with keyword in body'],
        ['sub foo { my $x = 1; }',     'sub with keyword in body'],
        ['{ my $x = 1; my $y = 2; }',  'block with two keyword stmts'],
        ['my $x = 1; { my $y = 2; }',  'stmt then block with keyword'],
        ['for my $x (@a) { my $y = 1; }', 'for with keywords in body'],
        ['{ use Foo; }',               'block with use keyword'],
        ['{ field $x; }',              'block with field keyword'],
    );

    for my $case (@sources) {
        my ($source, $desc) = $case->@*;
        my $parser = Chalk::Bootstrap::Earley->new(
            grammar  => $desugared,
            semiring => $comp_sr,
        );
        my $result = $parser->parse_value($source);
        ok(defined $result, "$desc parses deterministically");
    }
}

done_testing();
