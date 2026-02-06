# ABOUTME: Unit tests for Target::Perl code emitter.
# ABOUTME: Tests symbol/expression/rule emission and full generate() output.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

use Chalk::Bootstrap::IR::NodeFactory;

# Reset factory for clean test state
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# === Step 2: Scaffold ===

# Test 1: Module loads
use_ok('Chalk::Bootstrap::Target::Perl');

# Test 2: isa Target
my $target = Chalk::Bootstrap::Target::Perl->new();
isa_ok($target, 'Chalk::Bootstrap::Target');
isa_ok($target, 'Chalk::Bootstrap::Target::Perl');

# Test 3: generate([]) returns string with preamble
{
    my $output = $target->generate([]);
    like($output, qr/use 5\.42\.0/, 'output contains use 5.42.0');
    like($output, qr/use utf8/, 'output contains use utf8');
    like($output, qr/class Chalk::Grammar::BNF::Generated/, 'output contains class declaration');
    like($output, qr/sub grammar/, 'output contains grammar sub');
    like($output, qr/return \\/, 'output contains return statement');
}

# === Step 3: Symbol Emission ===

# Helper: build a Constructor:Symbol IR node
sub make_symbol {
    my (%args) = @_;
    my $type = $factory->make('Constant', const_type => 'enum', value => $args{type});
    my $value = $factory->make('Constant', const_type => 'string', value => $args{value});
    my $quant = $factory->make('Constant', const_type => 'string', value => $args{quantifier});
    return $factory->make('Constructor',
        class => 'Symbol',
        type => $type,
        value => $value,
        quantifier => $quant,
    );
}

# Test: Reference symbol emission
{
    my $sym = make_symbol(type => 'reference', value => 'Atom', quantifier => undef);
    my $code = $target->_emit_symbol($sym);
    like($code, qr/type => 'reference'/, 'reference symbol has correct type');
    like($code, qr/value => 'Atom'/, 'reference symbol has correct value');
    unlike($code, qr/quantifier/, 'reference symbol with undef quantifier omits it');
}

# Test: Terminal symbol — strips / delimiters
{
    my $sym = make_symbol(type => 'terminal', value => '/[A-Z]+/', quantifier => undef);
    my $code = $target->_emit_symbol($sym);
    like($code, qr/type => 'terminal'/, 'terminal symbol has correct type');
    like($code, qr/value => '\[A-Z\]\+'/, 'terminal symbol strips / delimiters');
    unlike($code, qr/quantifier/, 'terminal symbol with undef quantifier omits it');
}

# Test: Symbol with quantifier
{
    my $sym = make_symbol(type => 'reference', value => 'Rule', quantifier => '+');
    my $code = $target->_emit_symbol($sym);
    like($code, qr/quantifier => '\+'/, 'symbol with quantifier includes it');
}

# Test: Quantifier with single quote (defense-in-depth escaping test)
{
    my $sym = make_symbol(type => 'reference', value => 'Test', quantifier => "'");
    my $code = $target->_emit_symbol($sym);
    like($code, qr/quantifier => '\\''/, 'quantifier with single quote is escaped');
    unlike($code, qr/quantifier => '''/, 'quantifier single quote is not left unescaped');
}

# Test: Quantifier with backslash (defense-in-depth escaping test)
{
    my $sym = make_symbol(type => 'reference', value => 'Test', quantifier => '\\');
    my $code = $target->_emit_symbol($sym);
    like($code, qr/quantifier => '\\\\'/, 'quantifier with backslash is escaped (doubled)');
}

# Test: Complex escaping for single-quoted Perl strings
# IR value: /(?:\s|#[^\n]*)*/ -> strip -> (?:\s|#[^\n]*)*  -> escape -> (?:\\s|#[^\\n]*)*
{
    my $sym = make_symbol(type => 'terminal', value => '/(?:\\s|#[^\\n]*)*/', quantifier => undef);
    my $code = $target->_emit_symbol($sym);
    # After stripping delimiters: (?:\s|#[^\n]*)*
    # After escaping for single-quote: backslashes doubled
    like($code, qr/value => '/, 'terminal uses single-quoted value');
    # The escaped output should have doubled backslashes
    like($code, qr/\\\\s/, 'backslash-s becomes double-backslash-s in output');
    like($code, qr/\\\\n/, 'backslash-n becomes double-backslash-n in output');
}

# Test: Terminal without / delimiters (already stripped, e.g. '::=')
{
    my $sym = make_symbol(type => 'terminal', value => '/::=/', quantifier => undef);
    my $code = $target->_emit_symbol($sym);
    like($code, qr/value => '::='/, 'simple terminal value preserved after stripping');
}

# === Step 4: Expression Emission ===

# Helper: build a Constructor:Expression IR node from symbols
sub make_expression {
    my (@symbols) = @_;
    return $factory->make('Constructor',
        class => 'Expression',
        elements => \@symbols,
    );
}

# Test: Single-element expression
{
    my $sym = make_symbol(type => 'reference', value => 'Identifier', quantifier => undef);
    my $expr = make_expression($sym);
    my $code = $target->_emit_expression($expr);
    like($code, qr/\[/, 'expression starts with arrayref bracket');
    like($code, qr/Chalk::Grammar::Symbol->new/, 'expression contains symbol constructor');
    like($code, qr/\]/, 'expression ends with arrayref bracket');
}

# Test: Multi-element expression
{
    my $sym1 = make_symbol(type => 'reference', value => 'Identifier', quantifier => undef);
    my $sym2 = make_symbol(type => 'terminal', value => '/::=/', quantifier => undef);
    my $sym3 = make_symbol(type => 'reference', value => 'Alternatives', quantifier => undef);
    my $expr = make_expression($sym1, $sym2, $sym3);
    my $code = $target->_emit_expression($expr);
    # Should contain all 3 symbols separated by commas
    my @matches = ($code =~ /Chalk::Grammar::Symbol->new/g);
    is(scalar @matches, 3, 'multi-element expression has 3 symbols');
}

# === Step 5: Rule Emission ===

# Helper: build a Constructor:Rule IR node
sub make_rule {
    my ($name, @expressions) = @_;
    my $name_node = $factory->make('Constant', const_type => 'string', value => $name);
    return $factory->make('Constructor',
        class => 'Rule',
        name => $name_node,
        expressions => \@expressions,
    );
}

# Test: Single-alternative rule
{
    my $sym = make_symbol(type => 'terminal', value => '/[A-Za-z]+/', quantifier => undef);
    my $expr = make_expression($sym);
    my $rule = make_rule('Identifier', $expr);
    my $code = $target->_emit_rule($rule);
    like($code, qr/push \@rules/, 'rule starts with push');
    like($code, qr/Chalk::Grammar::Rule->new/, 'rule uses Rule constructor');
    like($code, qr/name => 'Identifier'/, 'rule name is correct');
    like($code, qr/expressions => \[/, 'rule has expressions arrayref');
}

# Test: Multi-alternative rule
{
    my $sym1 = make_symbol(type => 'reference', value => 'Identifier', quantifier => undef);
    my $sym2 = make_symbol(type => 'reference', value => 'InlineRegex', quantifier => undef);
    my $expr1 = make_expression($sym1);
    my $expr2 = make_expression($sym2);
    my $rule = make_rule('Atom', $expr1, $expr2);
    my $code = $target->_emit_rule($rule);
    # Should have 2 expression arrays (alternatives)
    my @expr_matches = ($code =~ /\[[\s\n]*Chalk::Grammar::Symbol/g);
    is(scalar @expr_matches, 2, 'multi-alternative rule has 2 expression arrays');
}

# Test: Rule name with single quote (defense-in-depth escaping test)
{
    my $sym = make_symbol(type => 'terminal', value => '/test/', quantifier => undef);
    my $expr = make_expression($sym);
    my $rule = make_rule("Test'Rule", $expr);
    my $code = $target->_emit_rule($rule);
    like($code, qr/name => 'Test\\'Rule'/, 'rule name with single quote is escaped');
    unlike($code, qr/name => 'Test'Rule'/, 'rule name single quote is not left unescaped');
}

# Test: Rule name with backslash (defense-in-depth escaping test)
{
    my $sym = make_symbol(type => 'terminal', value => '/test/', quantifier => undef);
    my $expr = make_expression($sym);
    my $rule = make_rule('Test\\Rule', $expr);
    my $code = $target->_emit_rule($rule);
    like($code, qr/name => 'Test\\\\Rule'/, 'rule name with backslash is escaped (doubled)');
}

# === Gap 3.3: Negative tests for malformed IR ===

# Test: generate(undef) dies with useful error
{
    my $target_neg = Chalk::Bootstrap::Target::Perl->new();
    eval { $target_neg->generate(undef); };
    like($@, qr/generate\(\) requires an arrayref/, 'generate(undef) dies with useful error');
}

# Test: generate("not an array") dies with useful error
{
    my $target_neg = Chalk::Bootstrap::Target::Perl->new();
    eval { $target_neg->generate("not an array"); };
    like($@, qr/generate\(\) requires an arrayref/, 'generate(non-arrayref) dies with useful error');
}

# === Step 6: Full generate() Assembly ===

# Test: generate() with IR rules produces valid Perl
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $sym1 = make_symbol(type => 'terminal', value => '/[A-Za-z_][A-Za-z_0-9]*/', quantifier => undef);
    my $expr1 = make_expression($sym1);
    my $rule1 = make_rule('Identifier', $expr1);

    my $sym2a = make_symbol(type => 'reference', value => 'Identifier', quantifier => undef);
    my $sym2b = make_symbol(type => 'reference', value => 'InlineRegex', quantifier => undef);
    my $expr2a = make_expression($sym2a);
    my $expr2b = make_expression($sym2b);
    my $rule2 = make_rule('Atom', $expr2a, $expr2b);

    my $target2 = Chalk::Bootstrap::Target::Perl->new();
    my $output = $target2->generate([$rule1, $rule2]);

    like($output, qr/push \@rules.*Identifier/s, 'generate() includes Identifier rule');
    like($output, qr/push \@rules.*Atom/s, 'generate() includes Atom rule');

    # eval the generated code — should not die
    eval $output;
    is($@, '', 'generated code evals without error');

    # Call the generated grammar()
    my $grammar = Chalk::Grammar::BNF::Generated::grammar();
    isa_ok($grammar, 'ARRAY', 'grammar() returns arrayref');
    is(scalar($grammar->@*), 2, 'grammar has 2 rules');

    # Verify rule names
    is($grammar->[0]->name(), 'Identifier', 'first rule name is Identifier');
    is($grammar->[1]->name(), 'Atom', 'second rule name is Atom');

    # Verify Identifier rule structure
    my $id_rule = $grammar->[0];
    is($id_rule->alternative_count(), 1, 'Identifier has 1 alternative');
    my $id_syms = $id_rule->expressions()->[0];
    is(scalar($id_syms->@*), 1, 'Identifier alternative has 1 symbol');
    ok($id_syms->[0]->is_terminal(), 'Identifier symbol is terminal');
    is($id_syms->[0]->value(), '[A-Za-z_][A-Za-z_0-9]*', 'Identifier terminal value correct');

    # Verify Atom rule structure
    my $atom_rule = $grammar->[1];
    is($atom_rule->alternative_count(), 2, 'Atom has 2 alternatives');
    ok($atom_rule->expressions()->[0][0]->is_reference(), 'Atom alt 1 is reference');
    is($atom_rule->expressions()->[0][0]->value(), 'Identifier', 'Atom alt 1 value is Identifier');
}

done_testing();
