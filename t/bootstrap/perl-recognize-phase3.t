# ABOUTME: Phase 3 test — class definitions recognition with the Perl grammar.
# ABOUTME: Tests class/sub/method definitions, attributes, signatures, and ADJUST blocks.
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
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::Phase3/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::Phase3::grammar();
    my $recognizer = build_perl_recognizer($gen_grammar, start => 'Program');

    skip 'Recognizer not built', 1 unless defined $recognizer;

    # §9 ClassBlock — minimal class
    ok($recognizer->parse('class Foo { }'),
        'Phase 3: accepts minimal class');
    ok($recognizer->parse('class Foo {}'),
        'Phase 3: accepts class with empty block');

    # §9 ClassBlock — with inheritance attribute
    ok($recognizer->parse('class Foo :isa(Bar) { }'),
        'Phase 3: accepts class with :isa');
    ok($recognizer->parse('class Foo :isa(Bar::Baz) { }'),
        'Phase 3: accepts class with qualified :isa');

    # §9 ClassBlock — with fields inside
    ok($recognizer->parse("class Foo {\n    field \$x :param :reader;\n}"),
        'Phase 3: accepts class with field declarations');
    ok($recognizer->parse("class Foo {\n    field \$x :param;\n    field \$y :param = undef;\n}"),
        'Phase 3: accepts class with multiple fields');

    # §9 ClassBlock — with method
    ok($recognizer->parse("class Foo {\n    field \$x :param;\n    method name() { }\n}"),
        'Phase 3: accepts class with field and method');

    # §9 SubroutineDefinition — basic sub
    ok($recognizer->parse('sub helper { }'),
        'Phase 3: accepts basic subroutine');
    ok($recognizer->parse('sub helper() { }'),
        'Phase 3: accepts sub with empty signature');
    ok($recognizer->parse('sub helper($arg) { }'),
        'Phase 3: accepts sub with signature');

    # §9 SubroutineDefinition — lexical sub
    ok($recognizer->parse('my sub _private { }'),
        'Phase 3: accepts my sub');
    ok($recognizer->parse('my sub _private($x) { }'),
        'Phase 3: accepts my sub with signature');
    ok($recognizer->parse('our sub exported($x) { }'),
        'Phase 3: accepts our sub with signature');
    ok($recognizer->parse('state sub memoized($x) { }'),
        'Phase 3: accepts state sub with signature');
    ok($recognizer->parse('our sub exported { }'),
        'Phase 3: accepts our sub without signature');
    ok($recognizer->parse('state sub memoized { }'),
        'Phase 3: accepts state sub without signature');

    # §9 MethodDefinition — basic method
    ok($recognizer->parse('method name() { }'),
        'Phase 3: accepts basic method');
    ok($recognizer->parse('method name { }'),
        'Phase 3: accepts method without signature');

    # §9 MethodDefinition — with signature params
    ok($recognizer->parse('method process($input, $output) { }'),
        'Phase 3: accepts method with multiple params');
    ok($recognizer->parse('method lookup($key, $default = undef) { }'),
        'Phase 3: accepts method with optional param');

    # §11 Signatures — slurpy params
    ok($recognizer->parse('method collect(@items) { }'),
        'Phase 3: accepts method with array slurpy');
    ok($recognizer->parse('method configure(%opts) { }'),
        'Phase 3: accepts method with hash slurpy');

    # §11 Signatures — mixed scalar and slurpy
    ok($recognizer->parse('method process($x, @rest) { }'),
        'Phase 3: accepts scalar then array slurpy');
    ok($recognizer->parse('method configure($name, %opts) { }'),
        'Phase 3: accepts scalar then hash slurpy');

    # §11 Signatures — trailing comma
    ok($recognizer->parse('method process($x, $y,) { }'),
        'Phase 3: accepts signature with trailing comma');

    # §11 Signatures — mixed scalar and default
    ok($recognizer->parse('method foo($a, $b = 1, $c = 2) { }'),
        'Phase 3: accepts multiple optional params');

    # §9 AdjustBlock
    ok($recognizer->parse('ADJUST { }'),
        'Phase 3: accepts standalone ADJUST block');
    ok($recognizer->parse("class Foo {\n    ADJUST { }\n}"),
        'Phase 3: accepts ADJUST inside class');

    # §10 AttributeList — multiple attributes
    ok($recognizer->parse('method name :lvalue() { }'),
        'Phase 3: accepts method with attribute');
    ok($recognizer->parse('method name :lvalue :reader() { }'),
        'Phase 3: accepts method with multiple attributes');
    ok($recognizer->parse('method transform :lvalue { }'),
        'Phase 3: accepts method with attribute but no signature');

    # §9 Full class combining everything (from test plan)
    ok($recognizer->parse("class Foo :isa(Bar) {\n    field \$name :param :reader;\n    field \$count :param = 0;\n    method increment() { }\n    ADJUST { }\n}"),
        'Phase 3: accepts full class with fields, methods, and ADJUST');

    # §13 AnonymousSub as atom in expression
    ok($recognizer->parse('my $f = sub { };'),
        'Phase 3: accepts anonymous sub assignment');
    ok($recognizer->parse('my $f = sub ($x) { };'),
        'Phase 3: accepts anonymous sub with signature');

    # Class with qualified name
    ok($recognizer->parse('class Foo::Bar { }'),
        'Phase 3: accepts class with qualified name');
    ok($recognizer->parse('class Foo::Bar :isa(Baz::Qux) { }'),
        'Phase 3: accepts class with qualified name and qualified :isa');

    # Multiple definitions in a program
    ok($recognizer->parse("sub helper(\$x) { }\nsub other(\$y) { }"),
        'Phase 3: accepts multiple subroutines');
    ok($recognizer->parse("class Foo { }\nclass Bar :isa(Foo) { }"),
        'Phase 3: accepts multiple class definitions');
    ok($recognizer->parse("use 5.42.0;\nuse utf8;\nclass Foo {\n    field \$x :param;\n    method name() { }\n}"),
        'Phase 3: accepts use declarations before class');

    # Nested blocks inside methods
    ok($recognizer->parse("method process() { { } }"),
        'Phase 3: accepts nested block inside method');

    # Negative cases
    # NOTE: Keywords (class, method, sub, ADJUST) are NOT reserved in this
    # grammar — they match Identifier and can appear in expression context
    # (e.g., "class;" is valid as an expression statement). The Boolean semiring
    # accepts all valid parses. These negative tests validate structural
    # incompleteness, not keyword semantics.
    ok(!$recognizer->parse('class { }'),
        'Phase 3: rejects "class { }" (no valid parse consumes full input)');
    ok(!$recognizer->parse('method () { }'),
        'Phase 3: rejects "method () { }" (no valid parse consumes full input)');
    ok(!$recognizer->parse('sub helper('),
        'Phase 3: rejects sub with unclosed signature');
    ok(!$recognizer->parse('class Foo {'),
        'Phase 3: rejects class with unclosed block');
    ok(!$recognizer->parse('method foo('),
        'Phase 3: rejects method with unclosed signature');
    ok(!$recognizer->parse('ADJUST'),
        'Phase 3: rejects bare ADJUST without block');
    ok(!$recognizer->parse('class Foo :isa( { }'),
        'Phase 3: rejects unclosed attribute parens');
    ok(!$recognizer->parse('class Foo { method }'),
        'Phase 3: rejects incomplete method inside class');
}

done_testing();
