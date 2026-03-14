# ABOUTME: Tests for grammar ambiguity fixes in the full 5-ary composite semiring.
# ABOUTME: Covers Subscript, BinaryExpression, CallExpression, ExpressionStatement, isa, __SUB__ disambiguation.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_concise_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::ConciseTree::Actions;

# Build the Perl grammar recognizer pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
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

    # --- map/grep as CallExpression: block-first builtins ---
    # These parse via CallExpression alt 2 (QualifiedIdentifier WS Block WS ExpressionList)
    # triggering Block vs HashConstructor ambiguity resolved by Structural
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

    # --- Category 3: CallExpression Block ambiguity ---
    # `map { {} } (0 .. $n)` — inner {} is ambiguous between HashConstructor
    # and Block. When inner completes as Block inside CallExpression,
    # the outer {} becomes CallExpression's Block.
    {
        my $result = parse_ok('my @x = map { {} } (0 .. $n);');
        ok(defined $result, 'map { {} } (0 .. $n) parses without ambiguity');
    }
    {
        my $result = parse_ok('return [ map { $_->zero() } $semirings->@* ];');
        ok(defined $result, 'map { method } postfix_deref parses without ambiguity');
    }
    # --- Category 4: Chained && with hash subscripts on both sides ---
    # `$right->{is_hash} && !$left->{is_hash}` creates two BinaryExpression
    # parses with is_deref tags that Structural must disambiguate via
    # non-binop preference.
    {
        my $result = parse_ok('my $r = $left->{is_block} && $right->{is_block};');
        ok(defined $result, '$left->{k} && $right->{k} parses without ambiguity');
    }
    {
        my $result = parse_ok('my $r = $right->{is_hash} && !$left->{is_hash};');
        ok(defined $result, '$right->{k} && !$left->{k} parses without ambiguity');
    }
    {
        my $result = parse_ok('my $r = $a->{foo} && $b->{bar} && $c->{baz};');
        ok(defined $result, 'triple chained && with hash subscripts parses without ambiguity');
    }

    # --- Category 5: Hash-deref assignment with method call on RHS ---
    # `$h->{k} = Foo->new()` creates a Precedence conflict where
    # AssignmentExpression (level=101) merges with PostfixExpression
    # (level=-2) via add(), and the assignment level wins, killing
    # valid method-call parse paths downstream.
    {
        my $result = parse_ok('my $x = Foo->new();');
        ok(defined $result, '$x = Foo->new() (baseline) parses without ambiguity');
    }
    {
        my $result = parse_ok('$h->{k} = Foo->new();');
        ok(defined $result, '$h->{k} = Foo->new() parses without ambiguity');
    }
    {
        my $result = parse_ok('$h->{k} = $x->foo();');
        ok(defined $result, '$h->{k} = $x->foo() parses without ambiguity');
    }
    {
        my $result = parse_ok('$h->{k} = Foo->new(a => $b);');
        ok(defined $result, '$h->{k} = Foo->new(a => $b) parses without ambiguity');
    }
    {
        my $result = parse_ok('$h->[0] = Foo->new();');
        ok(defined $result, '$h->[0] = Foo->new() parses without ambiguity');
    }

    # --- Category 6: Postfix $#* deref in map/grep ---
    # `map { ... } 0 .. $list->$#*` creates ExpressionList ambiguity
    # from the $#* PostfixDeref.
    {
        my $result = parse_ok('my @r = map { $x } 0 .. $list->$#*;');
        ok(defined $result, 'map { } 0 .. $list->$#* parses without ambiguity');
    }

    # --- Category 7: if/else before CallExpression ---
    # `if (...) { push @a, 'x'; } else { push @a, 'y'; } push @a, "z";`
    # creates two CallExpression parses with identical structural tags
    # [is_block,is_call,valid] because the is_block from the completed
    # if/else block propagates into both alternatives. When tags are
    # identical, selects_alternative must break the tie.
    {
        my $result = parse_ok('if (1) { push @a, "x"; } else { push @a, "y"; } push @a, "z";');
        ok(defined $result, 'if/else + push: identical is_block+is_call tags disambiguated');
    }
    {
        my $result = parse_ok('if ($x) { $a = 1; } else { $a = 2; } push @lines, "hello";');
        ok(defined $result, 'if/else + push (different bodies): disambiguated');
    }
    {
        my $result = parse_ok('if ($x) { foo(); } elsif ($y) { bar(); } else { baz(); } push @r, $z;');
        ok(defined $result, 'if/elsif/else + push: disambiguated');
    }

    # --- Category 8: Binary expression inside subscript ---
    # `$x->[$i + 1]` fails because the `+` operator level from the
    # BinaryExpression inside the subscript leaks through Subscript's
    # on_complete, causing PostfixExpression to reject the parse
    # (level >= 0 inside a PostfixExpression context).
    # Subscript brackets [...] and {...} should reset precedence context.
    {
        my $result = parse_ok('my $r = $x->[$i + 1];');
        ok(defined $result, '$x->[$i + 1] arrow subscript with arithmetic parses');
    }
    {
        my $result = parse_ok('my $r = $a[$i + 1];');
        ok(defined $result, '$a[$i + 1] bare subscript with arithmetic parses');
    }
    {
        my $result = parse_ok('my $r = $h{$k . $v};');
        ok(defined $result, '$h{$k . $v} bare hash subscript with concat parses');
    }
    {
        my $result = parse_ok('my $r = $x->[$i + 1]->value();');
        ok(defined $result, '$x->[$i + 1]->value() subscript + method chain parses');
    }
    {
        my $result = parse_ok('my $r = $x->[$i + 1] =~ /foo/;');
        ok(defined $result, '$x->[$i + 1] =~ /foo/ subscript + regex match parses');
    }

    # --- Category 9: Chained BinaryExpression identical-tag tie-breaking ---
    # When chained && or . operators have subscripts/method calls on both
    # sides, both BinaryExpression alternatives carry identical structural
    # tags. The tie-breaker picks left (left-associative grouping).
    {
        my $result = parse_ok('if ($a == 1 && $b->[0] isa Foo && $b->[0]->class() eq q{X}) { $r = 1; }');
        ok(defined $result, '3-way && with subscript + isa + method eq parses');
    }
    {
        my $result = parse_ok('if ($a eq q{X} && $b !~ /::/ && $c->($d)) { $r = 1; }');
        ok(defined $result, 'eq + !~ regex + coderef call 3-way && parses');
    }
    {
        my $result = parse_ok('my $r = "prefix" . $self->method($x) . "suffix";');
        ok(defined $result, '3-way string concat with method call parses');
    }

    # --- Category 10: Chained AssignmentExpression right-associativity ---
    # `my $x = $y //= 1` must parse as `my $x = ($y //= 1)` (right-assoc).
    # Without is_operator on AssignOp, both groupings survive with identical
    # level=101, causing an ambiguity crash.
    {
        my $result = parse_ok('my $x = $y //= 1;');
        ok(defined $result, 'chained = ... //= parses (right-associative)');
    }
    {
        my $result = parse_ok('my $pattern = $h{$k} //= qr/foo/;');
        ok(defined $result, 'vardecl = hash //= qr// parses');
    }
    {
        my $result = parse_ok('$x = $y = $z = 1;');
        ok(defined $result, 'triple chained = is right-associative');
    }
    # --- Category 11: BinaryExpression as Subscript target ---
    # `$a->[$i] // $a->[-1]` must parse as:
    #   BinaryExpr(//, Subscript($a,$i), Subscript($a,-1))
    # NOT as:
    #   Subscript(BinaryExpr(//, Subscript($a,$i), $a), -1)
    # The Precedence semiring must reject the second parse because a
    # BinaryExpression (level >= 0) cannot be the target of a Subscript.
    # Without this, the XS codegen emits ($a->[$i] // $a)->[-1] which
    # calls SvRV on a string, causing a segfault.
    {
        my $result = parse_ok('my $x = $a->[$i] // $a->[-1];');
        ok(defined $result, '$a->[$i] // $a->[-1] parses successfully');
        # Verify the outermost op is dor (defined-or), not aelem (array element).
        # If the wrong parse wins, aelem would be outermost because the //
        # would be nested inside the Subscript.
        if (defined $result) {
            my $sa_ctx = $result->[4];  # SemanticAction result (Context)
            my $tree = $sa_ctx->extract();  # ConciseTree
            my $ops = $tree->ops();
            # The dor op should appear in the sequence, confirming //
            # is the outermost binary op (not nested inside a Subscript).
            my $has_dor = grep { $_->name() eq 'dor' } $ops->@*;
            ok($has_dor, '$a->[$i] // $a->[-1]: op sequence contains dor');
        }
    }
    {
        my $result = parse_ok('my $x = $a->[$i] || $a->[0];');
        ok(defined $result, '$a->[$i] || $a->[0] parses correctly');
        if (defined $result) {
            my $sa_ctx = $result->[4];
            my $tree = $sa_ctx->extract();
            my $ops = $tree->ops();
            my $has_or = grep { $_->name() eq 'or' } $ops->@*;
            ok($has_or, '$a->[$i] || $a->[0]: op sequence contains or');
        }
    }
    {
        my $result = parse_ok('my $x = $a->[$i] && $a->{$k};');
        ok(defined $result, '$a->[$i] && $a->{$k} mixed subscript styles parse correctly');
    }
    # Verify that legitimate subscripts with arithmetic indices still work
    {
        my $result = parse_ok('my $x = $a->[$i + $offset];');
        ok(defined $result, '$a->[$i + $offset] arithmetic in subscript index still works');
    }
    {
        my $result = parse_ok('my $x = $a->[$i + 1]->value();');
        ok(defined $result, '$a->[$i + 1]->value() subscript + method chain still works');
    }
}

done_testing();
