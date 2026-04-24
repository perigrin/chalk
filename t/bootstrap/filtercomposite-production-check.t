# ABOUTME: Sanity check — does FilterComposite (production path) produce correct IR for known Perl snippets?
# ABOUTME: Verifies that the wrapper-loss bug is confined to Boolean-standalone and does not affect production.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Scalar::Util qw(blessed);

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
BAIL_OUT('Perl grammar failed to parse') unless defined $raw_ir;

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ProdCheck/g;
eval $generated;
BAIL_OUT("Generated code failed to compile: $@") if $@;

my $gen_grammar = Chalk::Grammar::Perl::ProdCheck::grammar();

# Test cases: snippets that should produce a specific IR node class.
# These are simple enough that any correct Perl parser should handle them.
my @cases = (
    ['42',            'Constant', 'integer literal'],
    ['"hello"',       'Constant', 'string literal'],
    ['$x',            'Constant', 'scalar variable'],
    ['1 + 2',         'Add',      'binary add'],
    ['1 + 2 * 3',     'Add',      'binary add with precedence'],
    ['$x + 1',        'Add',      'scalar binop'],
    ['foo()',         'Call',     'no-arg call'],
    ['foo(1)',        'Call',     'single-arg call'],
    ['foo(1, 2)',     'Call',     'multi-arg call'],
);

for my $case (@cases) {
    my ($input, $expected_class, $desc) = @$case;
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Expression');
    my $result = $parser->parse_value($input);

    ok(defined $result, "parses '$input' ($desc)");
    SKIP: {
        skip "parse failed for '$input'", 2 unless defined $result;

        my $ir = $result->extract();
        ok(defined $ir, "'$input' produces defined IR focus");

        SKIP: {
            skip "IR is undef for '$input'", 1 unless defined $ir;
            my $ir_class = ref($ir) // 'SCALAR';
            $ir_class =~ s/^Chalk::IR::Node:://;
            like($ir_class, qr/\Q$expected_class\E/,
                "'$input' IR class matches expected '$expected_class' (got '$ir_class')");
        }
    }
}

done_testing();
