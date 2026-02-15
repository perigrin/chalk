# ABOUTME: Unit tests for Target::XS code emitter.
# ABOUTME: Tests XS generation from IR nodes including scaffold, lowering, and full pipeline.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

# === Scaffold Tests ===

# Test: Module loads
use_ok('Chalk::Bootstrap::Target::XS');

# Test: isa Target
{
    my $target = Chalk::Bootstrap::Target::XS->new();
    isa_ok($target, 'Chalk::Bootstrap::Target');
    isa_ok($target, 'Chalk::Bootstrap::Target::XS');
}

# Test: generate([]) returns a string with preamble and module declaration
{
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $output = $target->generate([]);
    like($output, qr/#define PERL_NO_GET_CONTEXT/, 'scaffold contains PERL_NO_GET_CONTEXT');
    like($output, qr/#include "EXTERN\.h"/, 'scaffold contains EXTERN.h');
    like($output, qr/#include "perl\.h"/, 'scaffold contains perl.h');
    like($output, qr/#include "XSUB\.h"/, 'scaffold contains XSUB.h');
    like($output, qr/MODULE = Chalk::Grammar::BNF::Rules/, 'scaffold contains MODULE =');
    like($output, qr/PACKAGE = Chalk::Grammar::BNF::Rules/, 'scaffold contains PACKAGE =');
}

# Test: module_name is configurable
{
    my $target = Chalk::Bootstrap::Target::XS->new(module_name => 'Test::Module');
    my $output = $target->generate([]);
    like($output, qr/MODULE = Test::Module/, 'configurable module name in MODULE =');
    like($output, qr/PACKAGE = Test::Module/, 'configurable module name in PACKAGE =');
    is($target->module_name(), 'Test::Module', 'module_name reader works');
}

# Test: Invalid module names rejected at construction
{
    eval { Chalk::Bootstrap::Target::XS->new(module_name => "Foo'; system('bad')") };
    like($@, qr/Invalid module name/, 'module name with quotes rejected');

    eval { Chalk::Bootstrap::Target::XS->new(module_name => "../../../etc/passwd") };
    like($@, qr/Invalid module name/, 'module name with path traversal rejected');

    eval { Chalk::Bootstrap::Target::XS->new(module_name => "Foo\nBar") };
    like($@, qr/Invalid module name/, 'module name with newline rejected');

    eval { Chalk::Bootstrap::Target::XS->new(module_name => '') };
    like($@, qr/Invalid module name/, 'empty module name rejected');

    eval { Chalk::Bootstrap::Target::XS->new(module_name => 'Foo-Bar') };
    like($@, qr/Invalid module name/, 'module name with hyphen rejected');
}

# Test: Valid module names accepted
{
    my $t1 = Chalk::Bootstrap::Target::XS->new(module_name => 'Foo');
    is($t1->module_name(), 'Foo', 'single-segment module name accepted');

    my $t2 = Chalk::Bootstrap::Target::XS->new(module_name => 'Foo::Bar::Baz');
    is($t2->module_name(), 'Foo::Bar::Baz', 'multi-segment module name accepted');

    my $t3 = Chalk::Bootstrap::Target::XS->new(module_name => 'Foo_Bar::Baz2');
    is($t3->module_name(), 'Foo_Bar::Baz2', 'module name with underscores and digits accepted');
}

# Test: generate(undef) dies with useful error
{
    my $target = Chalk::Bootstrap::Target::XS->new();
    eval { $target->generate(undef) };
    like($@, qr/generate\(\) requires an arrayref/, 'generate(undef) dies with useful error');
}

# Test: generate("not an array") dies with useful error
{
    my $target = Chalk::Bootstrap::Target::XS->new();
    eval { $target->generate("not an array") };
    like($@, qr/generate\(\) requires an arrayref/, 'generate(non-arrayref) dies with useful error');
}

# === C String Escaping Tests ===

{
    my $target = Chalk::Bootstrap::Target::XS->new();

    # Plain string — no escaping needed
    is($target->_escape_c_string('hello'), 'hello', 'plain string passes through');

    # Backslash → double backslash
    is($target->_escape_c_string('a\\b'), 'a\\\\b', 'backslash is doubled');

    # Double quote → backslash double quote
    is($target->_escape_c_string('say "hi"'), 'say \\"hi\\"', 'double quotes are escaped');

    # Combined: both backslash and double quote
    is($target->_escape_c_string('a\\"b'), 'a\\\\\\"b', 'combined backslash and double quote');

    # Complex regex pattern from BNF meta-grammar
    # Input: (?:\s|#[^\n]*)* — contains backslashes
    is($target->_escape_c_string('(?:\\s|#[^\\n]*)*'),
       '(?:\\\\s|#[^\\\\n]*)*',
       'complex regex pattern escaping');

    # Control characters: actual newline byte → \n in C
    is($target->_escape_c_string("line1\nline2"), 'line1\\nline2',
        'actual newline byte escaped to \\n');

    # Control characters: actual tab byte → \t in C
    is($target->_escape_c_string("col1\tcol2"), 'col1\\tcol2',
        'actual tab byte escaped to \\t');

    # Control characters: actual carriage return → \r in C
    is($target->_escape_c_string("line1\rline2"), 'line1\\rline2',
        'actual carriage return escaped to \\r');

    # Null byte → \0 in C
    is($target->_escape_c_string("before\0after"), 'before\\0after',
        'null byte escaped to \\0');

    # Non-printable control characters → \xHH hex escapes
    is($target->_escape_c_string("\x01"), '\\x01',
        'SOH control character escaped to hex');
    is($target->_escape_c_string("\x0B"), '\\x0b',
        'vertical tab escaped to hex');
    is($target->_escape_c_string("\x0C"), '\\x0c',
        'form feed escaped to hex');
    is($target->_escape_c_string("\x1B"), '\\x1b',
        'escape character escaped to hex');
    is($target->_escape_c_string("\x7F"), '\\x7f',
        'DEL character escaped to hex');

    # High bytes (0x80+) → \xHH hex escapes
    is($target->_escape_c_string("\x80"), '\\x80',
        'high byte 0x80 escaped to hex');
    is($target->_escape_c_string("\xFF"), '\\xff',
        'high byte 0xFF escaped to hex');

    # Empty string → passes through unchanged
    is($target->_escape_c_string(''), '',
        'empty string passes through');

    # Mixed: printable + control in one string
    is($target->_escape_c_string("A\x01B"), 'A\\x01B',
        'mixed printable and control chars');
}

# === Terminal Delimiter Stripping ===

{
    my $target = Chalk::Bootstrap::Target::XS->new();

    # Strip / delimiters from terminal value
    is($target->_strip_terminal_delimiters('/[A-Z]+/'), '[A-Z]+',
        'strips / delimiters from terminal');

    # Non-delimited value passes through
    is($target->_strip_terminal_delimiters('::='), '::=',
        'non-delimited value passes through');

    # Value that starts with / but does not end with / passes through
    is($target->_strip_terminal_delimiters('/foo'), '/foo',
        'incomplete delimiters pass through');

    # Complex regex terminal
    is($target->_strip_terminal_delimiters('/(?:\\s|#[^\\n]*)*$/'),
        '(?:\\s|#[^\\n]*)*$',
        'complex regex terminal strips delimiters');
}

# === Constant Node Lowering ===

use Chalk::Bootstrap::IR::NodeFactory;

{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    my $target = Chalk::Bootstrap::Target::XS->new();

    # String constant → newSVpvs
    my $const = $factory->make('Constant', const_type => 'string', value => 'Grammar');
    is($target->_emit_constant($const), 'newSVpvs("Grammar")',
        'string constant emits newSVpvs');

    # Enum constant → newSVpvs (type names are strings too)
    my $enum = $factory->make('Constant', const_type => 'enum', value => 'reference');
    is($target->_emit_constant($enum), 'newSVpvs("reference")',
        'enum constant emits newSVpvs');

    # String with double quotes → newSVpvn (escaping changes length)
    my $quoted = $factory->make('Constant', const_type => 'string', value => 'say "hi"');
    is($target->_emit_constant($quoted), 'newSVpvn("say \\"hi\\"", 8)',
        'constant with double quotes uses newSVpvn with pre-escape length');

    # String with backslash → newSVpvn with pre-escape length
    my $bslash = $factory->make('Constant', const_type => 'string', value => 'a\\b');
    is($target->_emit_constant($bslash), 'newSVpvn("a\\\\b", 3)',
        'constant with backslash uses newSVpvn with pre-escape length');

    # String without backslash → newSVpvs (no length ambiguity)
    my $plain = $factory->make('Constant', const_type => 'string', value => 'hello');
    is($target->_emit_constant($plain), 'newSVpvs("hello")',
        'constant without escape-sensitive chars uses newSVpvs');

    # Empty string → newSVpvs
    my $empty = $factory->make('Constant', const_type => 'string', value => '');
    is($target->_emit_constant($empty), 'newSVpvs("")',
        'empty string constant uses newSVpvs');
}

# === Symbol Construction Lowering ===

# Helper: build a Constructor:Symbol IR node (same as codegen-perl.t)
sub make_symbol {
    my (%args) = @_;
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
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

# Test: Reference symbol without quantifier
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym = make_symbol(type => 'reference', value => 'Atom', quantifier => undef);

    my $nodes = $target->_emit_symbol($sym, 'sym_0');
    is(ref($nodes), 'ARRAY', '_emit_symbol returns arrayref');
    is(scalar $nodes->@*, 2, '_emit_symbol returns 2 nodes (VarDecl + Statement)');

    # First node is a VarDecl
    isa_ok($nodes->[0], 'Chalk::Bootstrap::Target::XS::AST::VarDecl');
    is($nodes->[0]->type(), 'SV *', 'VarDecl type is SV *');
    is($nodes->[0]->name(), 'sym_0', 'VarDecl name matches var_name arg');

    # Second node is a Statement with call_method block
    isa_ok($nodes->[1], 'Chalk::Bootstrap::Target::XS::AST::Statement');
    my $code = $nodes->[1]->code();
    like($code, qr/dSP/, 'call_method block has dSP');
    like($code, qr/ENTER; SAVETMPS/, 'call_method block has ENTER; SAVETMPS');
    like($code, qr/Chalk::Grammar::Symbol/, 'block pushes Symbol class name');
    like($code, qr/"type"/, 'block pushes type key');
    like($code, qr/"reference"/, 'block pushes reference type value');
    like($code, qr/"value"/, 'block pushes value key');
    like($code, qr/"Atom"/, 'block pushes Atom value');
    unlike($code, qr/quantifier/, 'block omits quantifier when undef');
    like($code, qr/call_method\("new", G_SCALAR\)/, 'block calls new');
    like($code, qr/sym_0 = SvREFCNT_inc\(POPs\)/, 'block assigns to sym_0');
    like($code, qr/FREETMPS; LEAVE/, 'block has FREETMPS; LEAVE');
}

# Test: Terminal symbol — value has delimiters stripped and C-escaped
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym = make_symbol(type => 'terminal', value => '/[A-Z]+/', quantifier => undef);

    my $nodes = $target->_emit_symbol($sym, 'sym_1');
    my $code = $nodes->[1]->code();
    like($code, qr/"terminal"/, 'terminal symbol has correct type');
    like($code, qr/"\[A-Z\]\+"/, 'terminal value has delimiters stripped');
    unlike($code, qr/\/\[A-Z\]\+\//, 'terminal value does not have / delimiters');
}

# Test: Symbol with quantifier — block includes quantifier args
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym = make_symbol(type => 'reference', value => 'Rule', quantifier => '+');

    my $nodes = $target->_emit_symbol($sym, 'sym_2');
    my $code = $nodes->[1]->code();
    like($code, qr/"quantifier"/, 'block includes quantifier key');
    like($code, qr/"\+"/, 'block includes + quantifier value');
}

# Test: Complex regex terminal — properly escaped in C string
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym = make_symbol(type => 'terminal', value => '/(?:\\s|#[^\\n]*)*/');

    my $nodes = $target->_emit_symbol($sym, 'sym_3');
    my $code = $nodes->[1]->code();
    # After stripping delimiters: (?:\s|#[^\n]*)*
    # After C escaping: (?:\\s|#[^\\n]*)*
    like($code, qr/\\\\s/, 'complex regex has escaped backslash-s');
    like($code, qr/\\\\n/, 'complex regex has escaped backslash-n');
}

# === Expression Construction Lowering ===

# Helper: build a Constructor:Expression IR node from symbols
sub make_expression {
    my (@symbols) = @_;
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    return $factory->make('Constructor',
        class => 'Expression',
        elements => \@symbols,
    );
}

# Helper: build a Constructor:Rule IR node
sub make_rule {
    my ($name, @expressions) = @_;
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    my $name_node = $factory->make('Constant', const_type => 'string', value => $name);
    return $factory->make('Constructor',
        class => 'Rule',
        name => $name_node,
        expressions => \@expressions,
    );
}

# Test: Single-symbol expression lowering
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym = make_symbol(type => 'reference', value => 'Identifier', quantifier => undef);
    my $expr = make_expression($sym);

    my $nodes = $target->_emit_expression($expr, 'expr_0');
    is(ref($nodes), 'ARRAY', '_emit_expression returns arrayref');

    # Should have: VarDecl(AV *expr_0), Statement(expr_0 = newAV()),
    #   symbol VarDecl, symbol Statement, Statement(av_push)
    ok(scalar $nodes->@* >= 4, '_emit_expression returns at least 4 nodes');

    # First node: VarDecl for AV *expr_0
    isa_ok($nodes->[0], 'Chalk::Bootstrap::Target::XS::AST::VarDecl');
    is($nodes->[0]->type(), 'AV *', 'expression VarDecl type is AV *');
    is($nodes->[0]->name(), 'expr_0', 'expression VarDecl name is expr_0');

    # Second node: Statement for newAV()
    isa_ok($nodes->[1], 'Chalk::Bootstrap::Target::XS::AST::Statement');
    like($nodes->[1]->code(), qr/expr_0 = newAV\(\)/, 'expression init with newAV()');

    # Last node: av_push statement
    my $last = $nodes->[-1];
    isa_ok($last, 'Chalk::Bootstrap::Target::XS::AST::Statement');
    like($last->code(), qr/av_push\(expr_0/, 'expression av_push to expr_0');
}

# Test: Multi-symbol expression
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym1 = make_symbol(type => 'reference', value => 'Identifier', quantifier => undef);
    my $sym2 = make_symbol(type => 'terminal', value => '/::=/', quantifier => undef);
    my $expr = make_expression($sym1, $sym2);

    my $nodes = $target->_emit_expression($expr, 'expr_0');

    # Count av_push statements (one per symbol)
    my @pushes = grep {
        $_ isa Chalk::Bootstrap::Target::XS::AST::Statement
        && $_->code() =~ /av_push/
    } $nodes->@*;
    is(scalar @pushes, 2, 'multi-symbol expression has 2 av_push statements');
}

# === Rule Construction Lowering ===

# Test: Single-alternative rule
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym = make_symbol(type => 'terminal', value => '/[A-Za-z]+/', quantifier => undef);
    my $expr = make_expression($sym);
    my $rule = make_rule('Identifier', $expr);

    my $nodes = $target->_emit_rule($rule);
    is(ref($nodes), 'ARRAY', '_emit_rule returns arrayref');

    # Check for VarDecls: AV *expressions, SV *rule (at minimum)
    my @var_decls = grep { $_ isa Chalk::Bootstrap::Target::XS::AST::VarDecl } $nodes->@*;
    ok(scalar @var_decls >= 2, 'rule has at least 2 VarDecls');

    # Check for expressions = newAV()
    my @init_stmts = grep {
        $_ isa Chalk::Bootstrap::Target::XS::AST::Statement
        && $_->code() =~ /expressions = newAV/
    } $nodes->@*;
    is(scalar @init_stmts, 1, 'rule has expressions = newAV() statement');

    # Check for av_push to expressions (one per alternative)
    my @expr_pushes = grep {
        $_ isa Chalk::Bootstrap::Target::XS::AST::Statement
        && $_->code() =~ /av_push\(expressions/
    } $nodes->@*;
    is(scalar @expr_pushes, 1, 'single-alt rule has 1 av_push to expressions');

    # Check for call_method block constructing Rule
    my @rule_blocks = grep {
        $_ isa Chalk::Bootstrap::Target::XS::AST::Statement
        && $_->code() =~ /Chalk::Grammar::Rule/
    } $nodes->@*;
    is(scalar @rule_blocks, 1, 'rule has call_method block for Rule constructor');

    # Check Rule call_method uses newRV_noinc for expressions
    like($rule_blocks[0]->code(), qr/newRV_noinc/, 'Rule constructor uses newRV_noinc');

    # Check for RETVAL assignment
    my @retval = grep {
        $_ isa Chalk::Bootstrap::Target::XS::AST::Statement
        && $_->code() =~ /RETVAL = rule/
    } $nodes->@*;
    is(scalar @retval, 1, 'rule has RETVAL = rule statement');

    # Check rule name appears in the call_method block
    like($rule_blocks[0]->code(), qr/"Identifier"/, 'Rule constructor has correct name');
}

# Test: Multi-alternative rule
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym1 = make_symbol(type => 'reference', value => 'Identifier', quantifier => undef);
    my $sym2 = make_symbol(type => 'reference', value => 'InlineRegex', quantifier => undef);
    my $expr1 = make_expression($sym1);
    my $expr2 = make_expression($sym2);
    my $rule = make_rule('Atom', $expr1, $expr2);

    my $nodes = $target->_emit_rule($rule);

    # 2 alternatives → 2 av_pushes to expressions
    my @expr_pushes = grep {
        $_ isa Chalk::Bootstrap::Target::XS::AST::Statement
        && $_->code() =~ /av_push\(expressions/
    } $nodes->@*;
    is(scalar @expr_pushes, 2, 'multi-alt rule has 2 av_pushes to expressions');
}

# === Counter reset between rules ===

# Test: Symbol/expression counters reset when _emit_rule is called multiple times
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();

    my $sym1 = make_symbol(type => 'reference', value => 'A', quantifier => undef);
    my $expr1 = make_expression($sym1);
    my $rule1 = make_rule('First', $expr1);

    my $sym2 = make_symbol(type => 'reference', value => 'B', quantifier => undef);
    my $expr2 = make_expression($sym2);
    my $rule2 = make_rule('Second', $expr2);

    # First call uses sym_0, expr_0
    $target->_emit_rule($rule1);

    # Second call should also use sym_0, expr_0 (counters reset)
    my $nodes2 = $target->_emit_rule($rule2);

    my @sym_decls = grep {
        $_ isa Chalk::Bootstrap::Target::XS::AST::VarDecl
        && $_->name() =~ /^sym_/
    } $nodes2->@*;
    is($sym_decls[0]->name(), 'sym_0', 'symbol counter resets between rules');

    my @expr_decls = grep {
        $_ isa Chalk::Bootstrap::Target::XS::AST::VarDecl
        && $_->name() =~ /^expr_/
    } $nodes2->@*;
    is($expr_decls[0]->name(), 'expr_0', 'expression counter resets between rules');
}

# === newSVpvn for terminal regex values ===

# Test: Terminal regex values use newSVpvn with explicit length
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym = make_symbol(type => 'terminal', value => '/[A-Z]+/', quantifier => undef);
    my $nodes = $target->_emit_symbol($sym, 'sym_0');
    my $code = $nodes->[1]->code();

    # Terminal values should use newSVpvn with explicit length per spec §5.4
    like($code, qr/newSVpvn\("[^"]+",\s*\d+\)/, 'terminal value uses newSVpvn with length');

    # Verify exact length: /[A-Z]+/ stripped to [A-Z]+ (6 chars), C-escaped stays [A-Z]+ (6 chars)
    like($code, qr/newSVpvn\("\[A-Z\]\+", 6\)/, 'newSVpvn length is exactly correct for [A-Z]+');
}

# Test: newSVpvn length is correct for terminals with backslashes (regression for length bug)
# The original bug computed length on the C-escaped string, but the C compiler
# interprets escape sequences (e.g. \\ → \), so the runtime byte count is smaller.
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();

    # /\d+/ strips to \d+ (3 bytes), C-escapes to \\d+ (4 chars in Perl source)
    # newSVpvn length MUST be 3 (pre-escaped), not 4 (post-escaped)
    my $sym_backslash = make_symbol(type => 'terminal', value => '/\\d+/', quantifier => undef);
    my $nodes_bs = $target->_emit_symbol($sym_backslash, 'sym_0');
    my $code_bs = $nodes_bs->[1]->code();

    like($code_bs, qr/newSVpvn\("\\\\d\+", 3\)/, 'newSVpvn length is 3 for \\d+ (pre-escaped, not post-escaped)');

    # /(?:\s|#[^\n]*)*/  strips to (?:\s|#[^\n]*)* (15 bytes), C-escapes to (?:\\s|#[^\\n]*)* (17 chars)
    # newSVpvn length MUST be 15, not 17
    my $sym_ws = make_symbol(type => 'terminal', value => '/(?:\\s|#[^\\n]*)*/', quantifier => undef);
    my $nodes_ws = $target->_emit_symbol($sym_ws, 'sym_1');
    my $code_ws = $nodes_ws->[1]->code();

    like($code_ws, qr/newSVpvn\("[^"]+", 15\)/, 'newSVpvn length is 15 for whitespace regex (pre-escaped, not 17)');
}

# Test: Non-terminal values still use newSVpvs
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym = make_symbol(type => 'reference', value => 'Atom', quantifier => undef);
    my $nodes = $target->_emit_symbol($sym, 'sym_0');
    my $code = $nodes->[1]->code();

    # Reference values use newSVpvs (compile-time sizeof)
    like($code, qr/newSVpvs\("Atom"\)/, 'reference value uses newSVpvs');
}

# === Graph Visitor + Full XSUB Assembly (Prompt 8) ===

# Test: _emit_xsub wraps a rule in an XSUB AST node
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym = make_symbol(type => 'terminal', value => '/[A-Za-z]+/', quantifier => undef);
    my $expr = make_expression($sym);
    my $rule = make_rule('Identifier', $expr);

    my $xsub = $target->_emit_xsub($rule);
    isa_ok($xsub, 'Chalk::Bootstrap::Target::XS::AST::XSUB', '_emit_xsub returns XSUB node');
    is($xsub->name(), 'Identifier', 'XSUB name matches rule name');
    is($xsub->return_type(), 'SV *', 'XSUB return type is SV *');

    my $output = $xsub->emit();
    like($output, qr/PREINIT:/, 'XSUB has PREINIT section');
    like($output, qr/CODE:/, 'XSUB has CODE section');
    like($output, qr/OUTPUT:\n    RETVAL/, 'XSUB has OUTPUT: RETVAL');
    like($output, qr/Identifier\(self\)/, 'XSUB signature has rule name');
}

# Test: _emit_xsub rejects rule names that are not valid C identifiers
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();

    # Rule name with C injection attempt
    my $sym = make_symbol(type => 'reference', value => 'Atom', quantifier => undef);
    my $expr = make_expression($sym);
    my $bad_rule = make_rule('foo; system("rm -rf /"); //', $expr);
    eval { $target->_emit_xsub($bad_rule) };
    like($@, qr/Invalid rule name/, '_emit_xsub rejects C injection in rule name');

    # Rule name with spaces
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $sym2 = make_symbol(type => 'reference', value => 'Atom', quantifier => undef);
    my $expr2 = make_expression($sym2);
    my $space_rule = make_rule('has space', $expr2);
    eval { $target->_emit_xsub($space_rule) };
    like($@, qr/Invalid rule name/, '_emit_xsub rejects rule name with spaces');

    # Rule name starting with digit
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $sym3 = make_symbol(type => 'reference', value => 'Atom', quantifier => undef);
    my $expr3 = make_expression($sym3);
    my $digit_rule = make_rule('1Rule', $expr3);
    eval { $target->_emit_xsub($digit_rule) };
    like($@, qr/Invalid rule name/, '_emit_xsub rejects rule name starting with digit');

    # Valid rule names still work
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $sym4 = make_symbol(type => 'reference', value => 'Atom', quantifier => undef);
    my $expr4 = make_expression($sym4);
    my $good_rule = make_rule('Grammar_v2', $expr4);
    my $xsub = eval { $target->_emit_xsub($good_rule) };
    is($@, '', '_emit_xsub accepts valid C identifier rule name');
    is($xsub->name(), 'Grammar_v2', 'XSUB name preserved for valid identifier');
}

# Test: generate() with single rule produces valid XS with 1 XSUB
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym = make_symbol(type => 'terminal', value => '/[A-Za-z]+/', quantifier => undef);
    my $expr = make_expression($sym);
    my $rule = make_rule('Identifier', $expr);

    my $output = $target->generate([$rule]);

    # Preamble still present
    like($output, qr/#define PERL_NO_GET_CONTEXT/, 'single rule XS has preamble');
    like($output, qr/MODULE = Chalk::Grammar::BNF::Rules/, 'single rule XS has MODULE');

    # XSUB present
    like($output, qr/^SV \*\nIdentifier\(self\)/m, 'single rule XS has Identifier XSUB');
    like($output, qr/PREINIT:/, 'single rule XSUB has PREINIT');
    like($output, qr/CODE:/, 'single rule XSUB has CODE');
    like($output, qr/OUTPUT:\n    RETVAL/, 'single rule XSUB has OUTPUT');
}

# Test: generate() with 2 rules produces XS with 2 XSUBs in order
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();

    my $sym1 = make_symbol(type => 'terminal', value => '/[A-Za-z]+/', quantifier => undef);
    my $expr1 = make_expression($sym1);
    my $rule1 = make_rule('Identifier', $expr1);

    my $sym2a = make_symbol(type => 'reference', value => 'Identifier', quantifier => undef);
    my $sym2b = make_symbol(type => 'reference', value => 'InlineRegex', quantifier => undef);
    my $expr2a = make_expression($sym2a);
    my $expr2b = make_expression($sym2b);
    my $rule2 = make_rule('Atom', $expr2a, $expr2b);

    my $output = $target->generate([$rule1, $rule2]);

    # Both XSUBs present
    like($output, qr/Identifier\(self\)/, '2-rule XS has Identifier XSUB');
    like($output, qr/Atom\(self\)/, '2-rule XS has Atom XSUB');

    # Identifier appears before Atom (order preserved)
    my $id_pos = index($output, 'Identifier(self)');
    my $atom_pos = index($output, 'Atom(self)');
    ok($id_pos < $atom_pos, 'Identifier XSUB appears before Atom XSUB');
}

# Test: Full 10-rule BNF meta-grammar integration via optimized_pipeline
use lib 't/bootstrap/lib';
use TestPipeline qw(optimized_pipeline);

{
    my $ir = optimized_pipeline();
    ok(defined $ir, 'optimized_pipeline returns IR');

    my $target = Chalk::Bootstrap::Target::XS->new();
    my $output = $target->generate($ir);

    # Preamble and MODULE present
    like($output, qr/#define PERL_NO_GET_CONTEXT/, 'full pipeline XS has preamble');
    like($output, qr/MODULE = Chalk::Grammar::BNF::Rules/, 'full pipeline XS has MODULE');

    # The BNF text defines 10 rules; desugared helpers (Rule_plus, etc.) are
    # parser infrastructure, not parsed output. IR has 10 Constructor:Rule nodes.
    for my $name (qw(Grammar Rule Alternatives Sequence Element Atom Quantifier Comment Identifier InlineRegex)) {
        like($output, qr/^SV \*\n\Q$name\E\(self\)/m,
            "full pipeline XS has $name XSUB");
    }

    # Each XSUB should have PREINIT, CODE, OUTPUT sections — exactly 10
    my @preinit_matches = ($output =~ /PREINIT:/g);
    is(scalar @preinit_matches, 10, "full pipeline XS has exactly 10 PREINIT sections");

    my @code_matches = ($output =~ /CODE:/g);
    is(scalar @code_matches, 10, "full pipeline XS has exactly 10 CODE sections");

    my @output_matches = ($output =~ /OUTPUT:/g);
    is(scalar @output_matches, 10, "full pipeline XS has exactly 10 OUTPUT sections");

    # Should contain call_method blocks for Symbol and Rule construction
    like($output, qr/call_method\("new", G_SCALAR\)/, 'full pipeline XS has call_method blocks');
    like($output, qr/Chalk::Grammar::Symbol/, 'full pipeline XS constructs Symbols');
    like($output, qr/Chalk::Grammar::Rule/, 'full pipeline XS constructs Rules');
}

# === Determinism Test (spec §5.5) ===

# Test: Same input produces byte-identical output across regenerations
{
    my $ir1 = optimized_pipeline();
    my $target1 = Chalk::Bootstrap::Target::XS->new();
    my $output1 = $target1->generate($ir1);

    my $ir2 = optimized_pipeline();
    my $target2 = Chalk::Bootstrap::Target::XS->new();
    my $output2 = $target2->generate($ir2);

    is($output1, $output2, 'XS output is deterministic across regenerations');
}

# === PM Stub Generation (Prompt 9) ===

# Test: _generate_pm_stub returns PMC stub with default module name
{
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $pmc = $target->_generate_pm_stub();

    like($pmc, qr/^# Generated by Chalk::Bootstrap compiler .* do not edit/, 'PMC has generated comment with do-not-edit');
    like($pmc, qr/package Chalk::Grammar::BNF::Rules;/, 'PMC has default package name');
    like($pmc, qr/use 5\.42\.0;/, 'PMC uses 5.42.0');
    like($pmc, qr/use XSLoader;/, 'PMC uses XSLoader');
    like($pmc, qr/our \$VERSION = '0\.01';/, 'PMC has VERSION');
    like($pmc, qr/XSLoader::load\(__PACKAGE__, \$VERSION\);/, 'PMC loads XS');
    like($pmc, qr/^1;\s*$/m, 'PMC ends with 1;');
}

# Test: _generate_pm_stub uses configurable module name
{
    my $target = Chalk::Bootstrap::Target::XS->new(module_name => 'My::Custom::Module');
    my $pmc = $target->_generate_pm_stub();

    like($pmc, qr/package My::Custom::Module;/, 'PMC has custom package name');
}

# === _module_path_prefix Direct Tests (Prompt 9) ===

# Test: _module_path_prefix with default module name
{
    my $target = Chalk::Bootstrap::Target::XS->new();
    is($target->_module_path_prefix(), 'lib/Chalk/Grammar/BNF/Rules',
        '_module_path_prefix returns correct path for default module');
}

# Test: _module_path_prefix with custom module name
{
    my $target = Chalk::Bootstrap::Target::XS->new(module_name => 'My::Custom::Module');
    is($target->_module_path_prefix(), 'lib/My/Custom/Module',
        '_module_path_prefix returns correct path for custom module');
}

# Test: _module_path_prefix with single-segment module name
{
    my $target = Chalk::Bootstrap::Target::XS->new(module_name => 'Foo');
    is($target->_module_path_prefix(), 'lib/Foo',
        '_module_path_prefix returns correct path for single-segment module');
}

# === Build.PL Generation (Prompt 9) ===

# Test: _generate_build_pl returns Module::Build script
{
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $build = $target->_generate_build_pl();

    like($build, qr/use Module::Build;/, 'Build.PL uses Module::Build');
    like($build, qr/module_name\s+=>\s+'Chalk::Grammar::BNF::Rules'/, 'Build.PL has module_name');
    like($build, qr/dist_version\s+=>\s+'0\.01'/, 'Build.PL has dist_version');
    like($build, qr/needs_compiler\s+=>\s+1\b/, 'Build.PL has needs_compiler');
    like($build, qr/xs_files/, 'Build.PL has xs_files');
    like($build, qr{lib/Chalk/Grammar/BNF/Rules\.xs}, 'Build.PL has correct .xs path');
    like($build, qr/create_build_script/, 'Build.PL calls create_build_script');

    # Verify xs_files key=>value pair: .xs maps to base path (no extension)
    like($build, qr{'lib/Chalk/Grammar/BNF/Rules\.xs'\s*=>\s*'lib/Chalk/Grammar/BNF/Rules'\s*\}},
        'Build.PL xs_files maps .xs to base path without extension');
}

# Test: _generate_build_pl uses configurable module name
{
    my $target = Chalk::Bootstrap::Target::XS->new(module_name => 'My::Custom::Module');
    my $build = $target->_generate_build_pl();

    like($build, qr/module_name\s+=>\s+'My::Custom::Module'/, 'Build.PL has custom module_name');
    like($build, qr{lib/My/Custom/Module\.xs}, 'Build.PL derives .xs path from custom module name');

    # Verify xs_files value-side for custom module name
    like($build, qr{'lib/My/Custom/Module\.xs'\s*=>\s*'lib/My/Custom/Module'\s*\}},
        'Build.PL custom xs_files maps .xs to base path without extension');
}

# === generate_distribution (Prompt 9) ===

# Test: generate_distribution returns hashref with 3 keys
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym = make_symbol(type => 'terminal', value => '/[A-Z]+/', quantifier => undef);
    my $expr = make_expression($sym);
    my $rule = make_rule('Test', $expr);

    my $dist = $target->generate_distribution([$rule]);
    is(ref($dist), 'HASH', 'generate_distribution returns hashref');

    my @keys = sort keys $dist->%*;
    is(scalar @keys, 3, 'distribution has 3 files');

    # Check expected keys
    ok(exists $dist->{'lib/Chalk/Grammar/BNF/Rules.xs'}, 'distribution has .xs key');
    ok(exists $dist->{'lib/Chalk/Grammar/BNF/Rules.pm'}, 'distribution has .pm key');
    ok(exists $dist->{'Build.PL'}, 'distribution has Build.PL key');
}

# Test: .xs content matches generate() output
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym = make_symbol(type => 'terminal', value => '/[A-Z]+/', quantifier => undef);
    my $expr = make_expression($sym);
    my $rule = make_rule('Test', $expr);

    my $dist = $target->generate_distribution([$rule]);
    my $direct = $target->generate([$rule]);

    is($dist->{'lib/Chalk/Grammar/BNF/Rules.xs'}, $direct,
        '.xs distribution content matches generate() output');
}

# Test: .pm content matches _generate_pm_stub() output
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym = make_symbol(type => 'terminal', value => '/[A-Z]+/', quantifier => undef);
    my $expr = make_expression($sym);
    my $rule = make_rule('Test', $expr);

    my $dist = $target->generate_distribution([$rule]);
    my $pmc = $target->_generate_pm_stub();

    is($dist->{'lib/Chalk/Grammar/BNF/Rules.pm'}, $pmc,
        '.pm distribution content matches _generate_pm_stub() output');
}

# Test: Build.PL content matches _generate_build_pl() output
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $sym = make_symbol(type => 'terminal', value => '/[A-Z]+/', quantifier => undef);
    my $expr = make_expression($sym);
    my $rule = make_rule('Test', $expr);

    my $dist = $target->generate_distribution([$rule]);
    my $build = $target->_generate_build_pl();

    is($dist->{'Build.PL'}, $build,
        'Build.PL distribution content matches _generate_build_pl() output');
}

# Test: File paths derive from custom module name
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $target = Chalk::Bootstrap::Target::XS->new(module_name => 'My::Custom::Module');
    my $sym = make_symbol(type => 'terminal', value => '/[A-Z]+/', quantifier => undef);
    my $expr = make_expression($sym);
    my $rule = make_rule('Test', $expr);

    my $dist = $target->generate_distribution([$rule]);

    ok(exists $dist->{'lib/My/Custom/Module.xs'}, 'custom module derives correct .xs path');
    ok(exists $dist->{'lib/My/Custom/Module.pm'}, 'custom module derives correct .pm path');
    ok(exists $dist->{'Build.PL'}, 'Build.PL key unchanged for custom module');
}

# Test: generate_distribution with empty IR produces 3-key hashref
{
    my $target = Chalk::Bootstrap::Target::XS->new();
    my $dist = $target->generate_distribution([]);
    is(ref($dist), 'HASH', 'empty IR distribution returns hashref');
    is(scalar keys $dist->%*, 3, 'empty IR distribution has 3 files');
    ok(exists $dist->{'lib/Chalk/Grammar/BNF/Rules.xs'}, 'empty IR distribution has .xs key');
}

# === Distribution Determinism (Prompt 9) ===

# Test: 3 generations produce identical .xs output
{
    my @outputs;
    for my $i (1..3) {
        my $ir = optimized_pipeline();
        my $target = Chalk::Bootstrap::Target::XS->new();
        push @outputs, $target->generate($ir);
    }

    is($outputs[0], $outputs[1], 'determinism: generation 1 == generation 2');
    is($outputs[1], $outputs[2], 'determinism: generation 2 == generation 3');
}

# Test: Full distribution determinism (all 3 files)
{
    my $ir1 = optimized_pipeline();
    my $target1 = Chalk::Bootstrap::Target::XS->new();
    my $dist1 = $target1->generate_distribution($ir1);

    my $ir2 = optimized_pipeline();
    my $target2 = Chalk::Bootstrap::Target::XS->new();
    my $dist2 = $target2->generate_distribution($ir2);

    for my $key (sort keys $dist1->%*) {
        is($dist1->{$key}, $dist2->{$key}, "distribution determinism: $key is byte-identical");
    }
}

done_testing();
