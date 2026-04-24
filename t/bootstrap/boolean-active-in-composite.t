# ABOUTME: Asserts Boolean actively runs under FilterComposite, writing the 'boolean' annotation slot.
# ABOUTME: Guards against Boolean regressing to vestigial status (slot_name=undef filtering it out).
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Semiring::Boolean;

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
BAIL_OUT('Perl grammar failed to parse') unless defined $raw_ir;

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::BoolActive/g;
eval $generated;
BAIL_OUT("Generated code failed to compile: $@") if $@;

my $gen_grammar = Chalk::Grammar::Perl::BoolActive::grammar();

# Count Boolean multiply invocations during a parse. If Boolean is truly
# running under FilterComposite, this must be non-zero for any non-trivial
# parse. If FilterComposite has silently filtered Boolean out (e.g., by
# slot_name returning undef), the counter stays zero.
our $bool_multiply_count = 0;
my $orig_multiply = \&Chalk::Bootstrap::Semiring::Boolean::multiply;
no warnings 'redefine';
*Chalk::Bootstrap::Semiring::Boolean::multiply = sub {
    $bool_multiply_count++;
    return $orig_multiply->(@_);
};

# Also assert Boolean declares a slot_name — the structural contract that
# gets it included in FilterComposite's _annotation_semirings filter.
{
    my $sr = Chalk::Bootstrap::Semiring::Boolean->new();
    ok(defined $sr->slot_name(),
        'Boolean declares a defined slot_name (required for FilterComposite inclusion)');
    is($sr->slot_name(), 'boolean',
        "Boolean's slot_name is 'boolean'");
}

# Parse a small Perl expression through the full FilterComposite stack.
# Boolean::multiply must fire at least once during the parse.
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Expression');
    my $result = $parser->parse_value('1 + 2');
    ok(defined $result, 'parses "1 + 2"');
    cmp_ok($bool_multiply_count, '>', 0,
        "Boolean::multiply fires under FilterComposite (count=$bool_multiply_count)");
}

# The returned Context must carry the 'boolean' annotation slot set by Boolean.
{
    $bool_multiply_count = 0;
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Expression');
    my $result = $parser->parse_value('42');
    ok(defined $result, 'parses "42"');
    my $boolean_slot = $result->annotations->{boolean};
    ok(defined $boolean_slot,
        "result Context has annotations->{boolean} set");
    ok($boolean_slot,
        "annotations->{boolean} is truthy (parse accepted)");
}

done_testing();
