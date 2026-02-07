# ABOUTME: Phase 2 test — declarations and literals recognition with the Perl grammar.
# ABOUTME: Tests use declarations, variable declarations, field declarations, and literal values.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_recognizer);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;

# Build the Perl grammar recognizer with Program as start symbol
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::Phase2/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::Phase2::grammar();
    my $recognizer = build_perl_recognizer($gen_grammar, start => 'Program');

    skip 'Recognizer not built', 1 unless defined $recognizer;

    # §7 Use declarations
    ok($recognizer->parse('use 5.42.0;'),
        'Phase 2: accepts version pragma');
    ok($recognizer->parse('use utf8;'),
        'Phase 2: accepts module use');
    ok($recognizer->parse("use experimental 'class';"),
        'Phase 2: accepts use with import list');
    ok($recognizer->parse('use experimental qw(class builtin);'),
        'Phase 2: accepts use with qw()');
    ok($recognizer->parse("use Exporter 'import';"),
        'Phase 2: accepts use with module and import');
    ok($recognizer->parse('use Chalk::Bootstrap::Earley;'),
        'Phase 2: accepts use with qualified module name');

    # §8 Variable declarations
    ok($recognizer->parse('my $x;'),
        'Phase 2: accepts bare scalar declaration');
    ok($recognizer->parse('my $x = 42;'),
        'Phase 2: accepts scalar with initializer');
    ok($recognizer->parse('my ($x, $y) = (1, 2);'),
        'Phase 2: accepts list variable declaration');
    ok($recognizer->parse("our \@EXPORT_OK = ('foo', 'bar');"),
        'Phase 2: accepts array declaration with initializer');
    ok($recognizer->parse('state %cache;'),
        'Phase 2: accepts state hash declaration');
    ok($recognizer->parse('local $x;'),
        'Phase 2: accepts local declaration');
    ok($recognizer->parse('my @array;'),
        'Phase 2: accepts array declaration');

    # §19 Literals as expression statements
    ok($recognizer->parse("'hello';"),
        'Phase 2: accepts single-quoted string');
    ok($recognizer->parse('"hello world";'),
        'Phase 2: accepts double-quoted string');
    ok($recognizer->parse('42;'),
        'Phase 2: accepts integer literal');
    ok($recognizer->parse('0xFF;'),
        'Phase 2: accepts hex literal');
    ok($recognizer->parse('3.14;'),
        'Phase 2: accepts float literal');
    ok($recognizer->parse('undef;'),
        'Phase 2: accepts undef literal');
    ok($recognizer->parse('true;'),
        'Phase 2: accepts true literal');
    ok($recognizer->parse('false;'),
        'Phase 2: accepts false literal');

    # §13 Array and hash constructors
    ok($recognizer->parse('[1, 2, 3];'),
        'Phase 2: accepts array constructor');
    ok($recognizer->parse('[];'),
        'Phase 2: accepts empty array constructor');
    ok($recognizer->parse('{};'),
        'Phase 2: accepts empty hash constructor');

    # §18 Variables as expressions
    ok($recognizer->parse('$x;'),
        'Phase 2: accepts scalar variable');
    ok($recognizer->parse('@array;'),
        'Phase 2: accepts array variable');
    ok($recognizer->parse('%hash;'),
        'Phase 2: accepts hash variable');

    # Combined declarations and expressions
    ok($recognizer->parse("use 5.42.0;\nuse utf8;\nmy \$x = 42;"),
        'Phase 2: accepts multiple use + declaration');
    ok($recognizer->parse("my \$x = 'hello';\nmy \$y = 42;"),
        'Phase 2: accepts multiple declarations');

    # Version and qualified identifier edge cases
    ok($recognizer->parse('use v5.42.0;'),
        'Phase 2: accepts version with v-prefix');
    ok($recognizer->parse('use Chalk::Grammar::BNF::Actions;'),
        'Phase 2: accepts deeply qualified module');
    ok($recognizer->parse("use Chalk::Bootstrap::Earley qw(parse);"),
        'Phase 2: accepts qualified module with qw import');

    # Numeric literal edge cases
    ok($recognizer->parse('0b1010;'),
        'Phase 2: accepts binary literal');
    ok($recognizer->parse('0o777;'),
        'Phase 2: accepts octal literal');
    ok($recognizer->parse('1_000_000;'),
        'Phase 2: accepts numeric with underscores');
    ok($recognizer->parse('1.5e10;'),
        'Phase 2: accepts scientific notation');

    # String literals
    ok($recognizer->parse("'it\\'s';"),
        'Phase 2: accepts escaped quote in string');
    ok($recognizer->parse('"hello\\nworld";'),
        'Phase 2: accepts escape sequence in double-quoted string');

    # §19 Regex literals (all five RegexLiteral alternatives)
    ok($recognizer->parse('/pattern/;'),
        'Phase 2: accepts bare regex literal');
    ok($recognizer->parse('/pattern/gi;'),
        'Phase 2: accepts regex with flags');
    ok($recognizer->parse('m/pattern/;'),
        'Phase 2: accepts m// regex');
    ok($recognizer->parse('qr/pattern/i;'),
        'Phase 2: accepts qr// regex');
    ok($recognizer->parse('s/foo/bar/g;'),
        'Phase 2: accepts s/// substitution');
    ok($recognizer->parse('s{foo}{bar}g;'),
        'Phase 2: accepts s{}{} substitution');

    # Field declarations (used in feature class)
    ok($recognizer->parse('field $x :param :reader;'),
        'Phase 2: accepts field with attributes');
    ok($recognizer->parse('field $x :param = undef;'),
        'Phase 2: accepts field with default value');

    # §13 QwLiteral as standalone expression
    ok($recognizer->parse('qw(foo bar baz);'),
        'Phase 2: accepts qw() as expression statement');
    ok($recognizer->parse('qw();'),
        'Phase 2: accepts empty qw()');

    # Expression list with fat comma and trailing comma
    ok($recognizer->parse("my %h = (a => 1, b => 2);"),
        'Phase 2: accepts hash-style list assignment');
    ok($recognizer->parse('[1, 2, 3,];'),
        'Phase 2: accepts array constructor with trailing comma');
    ok($recognizer->parse("my %h = (a => 1, b => 2,);"),
        'Phase 2: accepts hash-style list with trailing comma');

    # Note: keywords like 'use', 'my', 'field' are not reserved — they match
    # Identifier when not followed by expected syntax. E.g. 'use;' parses as
    # an expression statement. Disambiguation is handled by semirings, not
    # tested here.

    # Negative cases
    ok(!$recognizer->parse("'unclosed string;"),
        'Phase 2: rejects unclosed string');
    ok(!$recognizer->parse('my ($x, $y = ;'),
        'Phase 2: rejects malformed list declaration');
    ok(!$recognizer->parse('[1, 2, ;'),
        'Phase 2: rejects unclosed array constructor');
}

done_testing();
