# ABOUTME: Tests for grammar ambiguity fixes in the full 5-ary composite semiring.
# ABOUTME: Covers Subscript, BinaryExpression, MapGrepExpression, ExpressionStatement, isa, __SUB__ disambiguation.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_concise_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;
use Chalk::Bootstrap::ConciseTree::Actions;

# Build the Perl grammar recognizer pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::AmbigFixTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::AmbigFixTest::grammar();
    my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
    skip 'Concise parser not built', 1 unless defined $parser;

    # Helper to parse and check if result is defined (no ambiguity crash)
    my sub parse_ok($source) {
        my $result = $parser->parse_value($source);
        return undef unless defined $result;
        my $bool_val = $result->[0];
        return undef unless $bool_val;
        return $result;
    }

    # --- MapGrepExpression: map/grep with block and list ---
    # These trigger Atom ambiguity completing MapGrepExpression when there are
    # two alternatives: `map Block ExpressionList | map Block Expression`
    {
        my $result = parse_ok('my %h = map { $_ => 1 } qw(foo bar baz);');
        ok(defined $result, 'map { fat_comma } qw(...) parses without ambiguity');
    }
    {
        my $result = parse_ok('my @r = map { $_ } @list;');
        ok(defined $result, 'map { expr } @array parses without ambiguity');
    }
    {
        my $result = parse_ok('my @r = grep { $_ } @items;');
        ok(defined $result, 'grep { expr } @array parses without ambiguity');
    }

    # --- ExpressionStatement: Expression vs ExpressionList overlap ---
    # Large hash literals with many fat-comma pairs stress the
    # ExpressionStatement disambiguator
    {
        my $result = parse_ok('my %h = (a => 1, b => 2, c => 3);');
        ok(defined $result, 'hash literal with multiple fat-comma pairs parses');
    }

    # --- isa binary operator ---
    # `$x isa q{Foo}` creates BinaryExpression ambiguity when `q` is not
    # a keyword — it parses as both QualifiedIdentifier and string prefix.
    {
        my $result = parse_ok('my $r = $x isa q{Foo};');
        ok(defined $result, 'isa with q{} string parses without ambiguity');
    }
    {
        my $result = parse_ok('my $r = $x eq q[Bar];');
        ok(defined $result, 'eq with q[] string parses without ambiguity');
    }
    {
        my $result = parse_ok('my $r = qq{hello $x};');
        ok(defined $result, 'qq{} string literal parses without ambiguity');
    }

    # --- __SUB__ recursive closure ---
    # `__SUB__->($arg)` creates PostfixExpression ambiguity between
    # MethodCall and CoderefCall when __SUB__ parses as QualifiedIdentifier
    {
        my $result = parse_ok('my $f = sub { __SUB__->($x); };');
        ok(defined $result, '__SUB__->() recursive call parses without ambiguity');
    }

    # --- Category 1: Non-arrow Subscript ambiguity ---
    # `return $h{$k}` creates two PostfixExpression parses when non-arrow
    # Subscript (alts 3-4) lacks is_deref tag:
    #   Path A: CallExpression(return, Subscript($h, {$k})) — return takes hash value
    #   Path B: Subscript(CallExpression(return, $h), {$k}) — subscript return's result
    # Tagging all Subscript alts with is_deref lets add() prefer non-deref (Path A).
    {
        my $result = parse_ok('my $v = $h{$k};');
        ok(defined $result, '$h{$k} bare hash subscript parses without ambiguity');
    }
    {
        my $result = parse_ok('return $h{$k};');
        ok(defined $result, 'return $h{$k} parses without ambiguity');
    }
    {
        my $result = parse_ok('return $h[$i];');
        ok(defined $result, 'return $h[$i] parses without ambiguity');
    }
    {
        my $result = parse_ok('return $h{$k} // 0;');
        ok(defined $result, 'return $h{$k} // 0 parses without ambiguity');
    }
    {
        my $result = parse_ok('my $v = exists $helpers{$name};');
        ok(defined $result, 'exists $h{$k} parses without ambiguity');
    }

    # --- Category 2: Chained BinaryExpression + PostfixExpression ---
    # `$a && $b && $c->foo()` creates two BinaryExpression parses:
    #   Path A (correct): ($a && $b) && ($c->foo()) — left-associative
    #   Path B (wrong): $a && (($b && $c)->foo()) — method wraps inner &&
    # Path B survives because PostfixExpression on_complete assigns level=-2,
    # erasing the inner BinaryExpression's level=10.
    {
        my $result = parse_ok('my $r = $a && $b->foo();');
        ok(defined $result, '$a && $b->foo() (non-chained) parses without ambiguity');
    }
    {
        my $result = parse_ok('my $r = $a && $b && $c->foo();');
        ok(defined $result, '$a && $b && $c->foo() (chained) parses without ambiguity');
    }
    {
        my $result = parse_ok('my $r = $a && $b && $c->{$k};');
        ok(defined $result, '$a && $b && $c->{$k} (chained + subscript) parses without ambiguity');
    }
    {
        my $result = parse_ok('my $r = defined($ir) && $ir isa q{Foo} && $ir->class() eq q{Program};');
        ok(defined $result, 'defined() && isa && method chain parses without ambiguity');
    }
    {
        my $result = parse_ok('my $r = $x . $self->_escape($name) . $y;');
        ok(defined $result, 'string concat chain with method call parses without ambiguity');
    }

    # --- Category 3: MapGrepExpression Block ambiguity ---
    # `map { {} } (0 .. $n)` — inner {} is ambiguous between HashConstructor
    # and Block. When inner completes as Block inside MapGrepExpression,
    # the outer {} becomes MapGrepExpression's Block.
    {
        my $result = parse_ok('my @x = map { {} } (0 .. $n);');
        ok(defined $result, 'map { {} } (0 .. $n) parses without ambiguity');
    }
    {
        my $result = parse_ok('return [ map { $_->zero() } $semirings->@* ];');
        ok(defined $result, 'map { method } postfix_deref parses without ambiguity');
    }
}

done_testing();
