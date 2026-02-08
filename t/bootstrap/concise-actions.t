# ABOUTME: Tests for ConciseTree::Actions that map Perl grammar rules to ConciseOps.
# ABOUTME: Tests Phase 2-4 (declarations, class/sub/method, expressions) via actual parsing.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_concise_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;
use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::ConciseTree;
use Chalk::Bootstrap::ConciseTree::Actions;

# Build the Perl grammar recognizer pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ConciseActionsTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::ConciseActionsTest::grammar();
    my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
    skip 'Concise parser not built', 1 unless defined $parser;

    # Helper to parse and extract ConciseTree
    # Result tuple: [0]=Boolean, [1]=Precedence, [2]=TypeInference, [3]=Structural, [4]=SemanticAction
    my sub parse_concise($source) {
        my $result = $parser->parse_value($source);
        return undef unless defined $result;
        my $bool_val = $result->[0];
        my $sem_val = $result->[4];
        return undef unless $bool_val;
        return $sem_val->extract();
    }

    # Helper to get op names from a tree
    my sub op_names($tree) {
        return map { $_->name() } $tree->ops()->@*;
    }

    # --- Scalar assignment: my $x = 42 ---
    {
        my $tree = parse_concise('my $x = 42;');
        ok(defined $tree, 'scalar int assignment parses');
        isa_ok($tree, 'Chalk::Bootstrap::ConciseTree');

        my @names = op_names($tree);
        is_deeply(\@names, [qw(enter nextstate const padsv_store leave)],
            'my $x = 42 op sequence');

        my @consts = grep { $_->name() eq 'const' } $tree->ops()->@*;
        is($consts[0]->type_info(), 'IV 42', 'const is IV 42');

        my @stores = grep { $_->name() eq 'padsv_store' } $tree->ops()->@*;
        like($stores[0]->type_info(), qr/\$x/, 'padsv_store has $x');
        like($stores[0]->private(), qr{/LVINTRO}, 'padsv_store has /LVINTRO');
    }

    # --- String assignment: my $x = "hello" ---
    {
        my $tree = parse_concise('my $x = "hello";');
        ok(defined $tree, 'scalar string assignment parses');

        my @consts = grep { $_->name() eq 'const' } $tree->ops()->@*;
        like($consts[0]->type_info(), qr/PV/, 'const is PV for string');
    }

    # --- Float assignment: my $x = 3.14 ---
    {
        my $tree = parse_concise('my $x = 3.14;');
        ok(defined $tree, 'scalar float assignment parses');

        my @consts = grep { $_->name() eq 'const' } $tree->ops()->@*;
        like($consts[0]->type_info(), qr/NV/, 'const is NV for float');
    }

    # --- Bare declaration: my $x ---
    {
        my $tree = parse_concise('my $x;');
        ok(defined $tree, 'bare declaration parses');

        my @names = op_names($tree);
        is_deeply(\@names, [qw(enter nextstate padsv leave)],
            'my $x op sequence');

        my @padsv = grep { $_->name() eq 'padsv' } $tree->ops()->@*;
        like($padsv[0]->type_info(), qr/\$x/, 'padsv has $x');
        like($padsv[0]->private(), qr{/LVINTRO}, 'padsv has /LVINTRO');
    }

    # --- Array assignment: my @arr = (1, 2) ---
    {
        my $tree = parse_concise('my @arr = (1, 2);');
        ok(defined $tree, 'array assignment parses');

        my @names = op_names($tree);
        is_deeply(\@names,
            [qw(enter nextstate pushmark const const pushmark padav aassign leave)],
            'my @arr = (1, 2) op sequence');

        my @padav = grep { $_->name() eq 'padav' } $tree->ops()->@*;
        like($padav[0]->type_info(), qr/\@arr/, 'padav has @arr');
        like($padav[0]->private(), qr{/LVINTRO}, 'padav has /LVINTRO');
    }

    # --- Hash assignment: my %h = (a => 1, b => 2) ---
    # Fat comma LHS identifiers should produce const[PV "ident"]/BARE
    {
        my $tree = parse_concise('my %h = (a => 1, b => 2);');
        ok(defined $tree, 'hash assignment parses');

        my @names = op_names($tree);
        is_deeply(\@names,
            [qw(enter nextstate pushmark const const const const pushmark padhv aassign leave)],
            'my %h = (a => 1, b => 2) op sequence');

        my @consts = grep { $_->name() eq 'const' } $tree->ops()->@*;
        is(scalar @consts, 4, 'hash has 4 const ops (2 keys + 2 values)');

        SKIP: {
            skip 'wrong const count', 6 unless @consts == 4;
            is($consts[0]->type_info(), 'PV "a"', 'first key is PV "a"');
            like($consts[0]->private(), qr{/BARE}, 'first key has /BARE');
            is($consts[1]->type_info(), 'IV 1', 'first value is IV 1');
            is($consts[2]->type_info(), 'PV "b"', 'second key is PV "b"');
            like($consts[2]->private(), qr{/BARE}, 'second key has /BARE');
            is($consts[3]->type_info(), 'IV 2', 'second value is IV 2');
        }

        my @padhv = grep { $_->name() eq 'padhv' } $tree->ops()->@*;
        like($padhv[0]->type_info(), qr/%h/, 'padhv has %h');
        like($padhv[0]->private(), qr{/LVINTRO}, 'padhv has /LVINTRO');
    }

    # --- Simple fat comma: my %h = (a => 1) ---
    {
        my $tree = parse_concise('my %h = (a => 1);');
        ok(defined $tree, 'simple fat comma parses');

        my @consts = grep { $_->name() eq 'const' } $tree->ops()->@*;
        is(scalar @consts, 2, 'simple fat comma has 2 const ops');

        SKIP: {
            skip 'wrong const count', 3 unless @consts == 2;
            is($consts[0]->type_info(), 'PV "a"', 'simple fat comma key is PV "a"');
            like($consts[0]->private(), qr{/BARE}, 'simple fat comma key has /BARE');
            is($consts[1]->type_info(), 'IV 1', 'simple fat comma value is IV 1');
        }
    }

    # --- Multiple statements ---
    {
        my $tree = parse_concise('my $x = 1; my $y = 2;');
        ok(defined $tree, 'two statements parse');

        my @names = op_names($tree);
        my @nextstates = grep { $_ eq 'nextstate' } @names;
        is(scalar @nextstates, 2, 'two statements have 2 nextstates');
        my @stores = grep { $_ eq 'padsv_store' } @names;
        is(scalar @stores, 2, 'two statements have 2 padsv_store');
    }

    # --- Compile-time only: use 5.42.0; use utf8 ---
    {
        my $tree = parse_concise('use 5.42.0; use utf8;');
        ok(defined $tree, 'compile-time only parses');

        my @names = op_names($tree);
        is_deeply(\@names, [qw(enter stub leave)],
            'compile-time only has enter stub leave');
    }

    # --- UseDeclaration produces empty tree (no runtime ops) ---
    {
        my $tree = parse_concise('use 5.42.0;');
        ok(defined $tree, 'single use parses');

        my @names = op_names($tree);
        ok((grep { $_ eq 'enter' } @names), 'single use has enter');
        ok((grep { $_ eq 'leave' } @names), 'single use has leave');
    }

    # --- Two-statement with different types ---
    {
        my $tree = parse_concise('my $x = "hello"; my $y = 3.14;');
        ok(defined $tree, 'mixed type two statements parse');

        my @consts = grep { $_->name() eq 'const' } $tree->ops()->@*;
        is(scalar @consts, 2, 'mixed types have 2 consts');
        like($consts[0]->type_info(), qr/PV/, 'first const is PV');
        like($consts[1]->type_info(), qr/NV/, 'second const is NV');
    }

    # ========================================================================
    # Regex literals
    # ========================================================================

    # --- RegexLiteral action exists ---
    {
        my $actions = Chalk::Bootstrap::ConciseTree::Actions->new();
        ok($actions->can('RegexLiteral'), 'RegexLiteral action method exists');
    }

    # --- Bare regex: my $x = /foo/; → match(/"foo"/) ---
    {
        my $tree = parse_concise('my $x = /foo/;');
        ok(defined $tree, 'bare regex assignment parses');

        my @names = op_names($tree);
        is_deeply(\@names, [qw(enter nextstate match padsv_store leave)],
            'my $x = /foo/ op sequence');

        my @match = grep { $_->name() eq 'match' } $tree->ops()->@*;
        is(scalar @match, 1, 'exactly one match op');
        SKIP: {
            skip 'no match op found', 2 unless @match;
            is($match[0]->type_info(), '/"foo"/', 'match has type_info /"foo"/');
            is($match[0]->arity(), '/', 'match has arity /');
        }
    }

    # --- qr// regex: my $x = qr/foo/; → qr(/"foo"/) ---
    {
        my $tree = parse_concise('my $x = qr/foo/;');
        ok(defined $tree, 'qr regex assignment parses');

        my @qr = grep { $_->name() eq 'qr' } $tree->ops()->@*;
        is(scalar @qr, 1, 'exactly one qr op');
        SKIP: {
            skip 'no qr op found', 2 unless @qr;
            is($qr[0]->type_info(), '/"foo"/', 'qr has type_info /"foo"/');
            is($qr[0]->arity(), '/', 'qr has arity /');
        }
    }

    # --- s/// substitution: my $x = s/foo/bar/; → const[PV "bar"] + subst(/"foo"/) ---
    {
        my $tree = parse_concise('my $x = s/foo/bar/;');
        ok(defined $tree, 'substitution assignment parses');

        my @subst = grep { $_->name() eq 'subst' } $tree->ops()->@*;
        is(scalar @subst, 1, 'exactly one subst op');
        SKIP: {
            skip 'no subst op found', 2 unless @subst;
            is($subst[0]->type_info(), '/"foo"/', 'subst has type_info /"foo"/');
            is($subst[0]->arity(), '/', 'subst has arity /');
        }

        # replacement string should be a const before the subst
        my @consts = grep { $_->name() eq 'const' } $tree->ops()->@*;
        ok((grep { $_->type_info() && $_->type_info() eq 'PV "bar"' } @consts),
            'substitution has const[PV "bar"] for replacement');
    }

    # --- m// regex: my $x = m/foo/; → match(/"foo"/) ---
    # Note: m{foo} is ambiguous with Identifier("m") + Block("{foo}"),
    # and the Structural semiring prefers Block. Using m// avoids this.
    {
        my $tree = parse_concise('my $x = m/foo/;');
        ok(defined $tree, 'm// regex assignment parses');

        my @match = grep { $_->name() eq 'match' } $tree->ops()->@*;
        is(scalar @match, 1, 'exactly one match op for m//');
        SKIP: {
            skip 'no match op found', 1 unless @match;
            is($match[0]->type_info(), '/"foo"/', 'm// match has type_info /"foo"/');
        }
    }

    # --- Regex with flags: my $x = /foo/gi; ---
    {
        my $tree = parse_concise('my $x = /foo/gi;');
        ok(defined $tree, 'regex with flags parses');

        my @match = grep { $_->name() eq 'match' } $tree->ops()->@*;
        is(scalar @match, 1, 'flagged regex has one match op');
        SKIP: {
            skip 'no match op found', 1 unless @match;
            is($match[0]->type_info(), '/"foo"/', 'flagged regex match has type_info /"foo"/');
        }
    }

    # --- Regex with escaped slash: my $x = /foo\/bar/; ---
    {
        my $tree = parse_concise('my $x = /foo\/bar/;');
        ok(defined $tree, 'escaped slash regex parses');

        my @match = grep { $_->name() eq 'match' } $tree->ops()->@*;
        is(scalar @match, 1, 'escaped slash regex has one match op');
        SKIP: {
            skip 'no match op found', 1 unless @match;
            is($match[0]->type_info(), '/"foo\/bar"/', 'escaped slash preserved in type_info');
        }
    }

    # --- s{}{} brace-delimited substitution: my $x = s{foo}{bar}; ---
    {
        my $tree = parse_concise('my $x = s{foo}{bar};');
        ok(defined $tree, 's{}{} substitution parses');

        my @subst = grep { $_->name() eq 'subst' } $tree->ops()->@*;
        is(scalar @subst, 1, 's{}{} has one subst op');
        SKIP: {
            skip 'no subst op found', 1 unless @subst;
            is($subst[0]->type_info(), '/"foo"/', 's{}{} subst has type_info /"foo"/');
        }

        my @consts = grep { $_->name() eq 'const' } $tree->ops()->@*;
        ok((grep { $_->type_info() && $_->type_info() eq 'PV "bar"' } @consts),
            's{}{} has const[PV "bar"] for replacement');
    }

    # --- Three-pair fat comma: my %h = (a => 1, b => 2, c => 3) ---
    {
        my $tree = parse_concise('my %h = (a => 1, b => 2, c => 3);');
        ok(defined $tree, 'three-pair fat comma parses');

        my @consts = grep { $_->name() eq 'const' } $tree->ops()->@*;
        is(scalar @consts, 6, 'three pairs produce 6 const ops');

        SKIP: {
            skip 'wrong const count', 6 unless @consts == 6;
            is($consts[0]->type_info(), 'PV "a"', 'three-pair: key a');
            like($consts[0]->private(), qr{/BARE}, 'three-pair: key a has /BARE');
            is($consts[1]->type_info(), 'IV 1', 'three-pair: value 1');
            is($consts[2]->type_info(), 'PV "b"', 'three-pair: key b');
            like($consts[2]->private(), qr{/BARE}, 'three-pair: key b has /BARE');
            is($consts[4]->type_info(), 'PV "c"', 'three-pair: key c');
            like($consts[4]->private(), qr{/BARE}, 'three-pair: key c has /BARE');
        }
    }

    # ========================================================================
    # Phase 3: Class definitions, subroutines, methods
    # ========================================================================

    # --- Named sub: compile-time only (enter stub leave) ---
    {
        my $tree = parse_concise('sub foo { }');
        ok(defined $tree, 'named sub parses');

        my @names = op_names($tree);
        is_deeply(\@names, [qw(enter stub leave)],
            'named sub produces enter stub leave');
    }

    # --- Named sub with body: compile-time (body ops in sub's own pad) ---
    # TypeInference rejects 'sub' as Identifier, so SubroutineDefinition
    # always wins. Body ops don't leak to the program-level optree.
    {
        my $tree = parse_concise('sub foo { return 42; }');
        ok(defined $tree, 'named sub with body parses');

        my @names = op_names($tree);
        is_deeply(\@names, [qw(enter stub leave)],
            'named sub with body: enter stub leave');
    }

    # --- Named sub with signature: compile-time ---
    {
        my $tree = parse_concise('sub foo($x, $y) { return $x; }');
        ok(defined $tree, 'named sub with signature parses');

        my @names = op_names($tree);
        is_deeply(\@names, [qw(enter stub leave)],
            'named sub with signature: enter stub leave');
    }

    # --- Multiple named subs: still compile-time ---
    {
        my $tree = parse_concise('sub foo { } sub bar { }');
        ok(defined $tree, 'multiple named subs parse');

        my @names = op_names($tree);
        is_deeply(\@names, [qw(enter stub leave)],
            'multiple named subs: enter stub leave');
    }

    # --- Anonymous sub assigned to variable ---
    # TypeInference rejects 'sub' as Identifier, so AnonymousSub action
    # always fires and produces anoncode.
    {
        my $tree = parse_concise('my $x = sub { return 42; };');
        ok(defined $tree, 'anonymous sub assignment parses');

        my @names = op_names($tree);
        is_deeply(\@names, [qw(enter nextstate anoncode padsv_store leave)],
            'my $x = sub { return 42; } op sequence');

        my @anoncode = grep { $_->name() eq 'anoncode' } $tree->ops()->@*;
        is(scalar @anoncode, 1, 'exactly one anoncode op');
        SKIP: {
            skip 'no anoncode op found', 1 unless @anoncode;
            is($anoncode[0]->type_info(), 'CV CODE', 'anoncode has CV CODE type_info');
        }
    }

    # --- Anonymous sub with empty body ---
    {
        my $tree = parse_concise('my $f = sub { };');
        ok(defined $tree, 'empty anonymous sub parses');

        my @names = op_names($tree);
        is_deeply(\@names, [qw(enter nextstate anoncode padsv_store leave)],
            'my $f = sub { } op sequence');
    }

    # --- AnonymousSub action unit test: verify it produces anoncode ---
    # Test the action method directly to ensure it returns the right op,
    # independent of grammar ambiguity.
    {
        my $actions = Chalk::Bootstrap::ConciseTree::Actions->new();
        ok($actions->can('AnonymousSub'), 'AnonymousSub action method exists');

        # Create a minimal context for the action
        my $ctx = Chalk::Bootstrap::Context->new(
            focus    => undef,
            children => [],
            position => 0,
            rule     => 'AnonymousSub',
        );
        my $tree = $actions->AnonymousSub($ctx);
        isa_ok($tree, 'Chalk::Bootstrap::ConciseTree');
        is($tree->op_count(), 1, 'AnonymousSub produces exactly 1 op');
        is($tree->ops()->[0]->name(), 'anoncode', 'AnonymousSub produces anoncode op');
        is($tree->ops()->[0]->type_info(), 'CV CODE', 'anoncode has CV CODE type_info');
    }

    # --- Direct action unit tests for compile-time methods ---
    # Verify each Phase 3 action method returns the expected result,
    # independent of grammar ambiguity.
    {
        my $actions = Chalk::Bootstrap::ConciseTree::Actions->new();
        my $empty_ctx = Chalk::Bootstrap::Context->new(
            focus    => undef,
            children => [],
            position => 0,
            rule     => undef,
        );

        # Compile-time only methods should return empty trees
        for my $method_name (qw(
            SubroutineDefinition ClassBlock MethodDefinition AdjustBlock
            AttributeList Attribute
            Signature SignatureParams SignatureParam
            ScalarSignatureParam SlurpySignatureParam
        )) {
            ok($actions->can($method_name), "$method_name action method exists");
            my $tree = $actions->$method_name($empty_ctx);
            isa_ok($tree, 'Chalk::Bootstrap::ConciseTree');
            is($tree->op_count(), 0, "$method_name returns empty tree");
        }

        # Transparent pass-through methods should work on empty context
        for my $method_name (qw(CompoundStatement Block)) {
            ok($actions->can($method_name), "$method_name action method exists");
            my $tree = $actions->$method_name($empty_ctx);
            isa_ok($tree, 'Chalk::Bootstrap::ConciseTree');
            is($tree->op_count(), 0, "$method_name on empty ctx returns empty tree");
        }
    }

    # --- Block as compound statement (bare block) ---
    {
        my $tree = parse_concise('{ my $x = 42; }');
        ok(defined $tree, 'bare block parses');

        my @names = op_names($tree);
        # Block contents should pass through
        ok((grep { $_ eq 'padsv_store' } @names),
            'bare block passes through child ops');
    }

    # --- CompoundStatement transparent pass-through ---
    {
        my $tree = parse_concise('sub foo { } my $x = 1;');
        ok(defined $tree, 'compound + simple statement parses');

        my @names = op_names($tree);
        # The sub is compile-time, the var decl produces runtime ops
        ok((grep { $_ eq 'padsv_store' } @names),
            'variable after sub produces padsv_store');
    }

    # ========================================================================
    # Phase 4: Expressions
    # ========================================================================

    # --- Binary arithmetic (uses variable operands to avoid constant folding) ---
    # Note: + and - are omitted because they have unary counterparts (/\+/, /-/)
    # that win disambiguation in the ambiguous grammar. Precedence semiring needed.
    {
        my $tree = parse_concise('my $a = 1; my $b = 2; my $c = $a * $b;');
        ok(defined $tree, 'multiplication expression parses');
        ok((grep { $_->name() eq 'multiply' } $tree->ops()->@*),
            'multiplication has multiply op');
    }

    {
        my $tree = parse_concise('my $a = 1; my $b = 2; my $c = $a ** $b;');
        ok(defined $tree, 'exponentiation expression parses');
        ok((grep { $_->name() eq 'pow' } $tree->ops()->@*),
            'exponentiation has pow op');
    }

    {
        my $tree = parse_concise('my $a = 1; my $b = 2; my $c = $a % $b;');
        ok(defined $tree, 'modulus expression parses');
        ok((grep { $_->name() eq 'modulo' } $tree->ops()->@*),
            'modulus has modulo op');
    }

    {
        my $tree = parse_concise('my $a = "x"; my $b = 3; my $c = $a x $b;');
        ok(defined $tree, 'repeat expression parses');
        ok((grep { $_->name() eq 'repeat' } $tree->ops()->@*),
            'repeat has repeat op');
    }

    # --- Comparison operators ---
    {
        my $tree = parse_concise('my $a = 1; my $b = 2; my $c = $a == $b;');
        ok(defined $tree, 'numeric equality parses');
        ok((grep { $_->name() eq 'eq' } $tree->ops()->@*),
            'numeric equality has eq op');
    }

    {
        my $tree = parse_concise('my $a = "x"; my $b = "y"; my $c = $a eq $b;');
        ok(defined $tree, 'string equality parses');
        ok((grep { $_->name() eq 'seq' } $tree->ops()->@*),
            'string equality has seq op');
    }

    # --- Unary operators ---
    {
        my $tree = parse_concise('my $a = 1; my $b = -$a;');
        ok(defined $tree, 'unary negation parses');
        ok((grep { $_->name() eq 'negate' } $tree->ops()->@*),
            'unary negation has negate op');
    }

    {
        my $tree = parse_concise('my $a = 1; my $b = not $a;');
        ok(defined $tree, 'unary not parses');
        ok((grep { $_->name() eq 'not' } $tree->ops()->@*),
            'unary not has not op');
    }

    {
        my $tree = parse_concise('my $a = 1; my $b = !$a;');
        ok(defined $tree, 'unary ! parses');
        ok((grep { $_->name() eq 'not' } $tree->ops()->@*),
            'unary ! has not op');
    }

    # --- Short-circuit operators (structural only — branching arity) ---
    {
        my $tree = parse_concise('my $a = 1; my $b = 2; my $c = $a && $b;');
        ok(defined $tree, 'logical and parses');
        ok((grep { $_->name() eq 'and' } $tree->ops()->@*),
            'logical and has and op');
    }

    {
        my $tree = parse_concise('my $a = 1; my $b = 2; my $c = $a || $b;');
        ok(defined $tree, 'logical or parses');
        ok((grep { $_->name() eq 'or' } $tree->ops()->@*),
            'logical or has or op');
    }

    # Note: // (defined-or) is omitted because it's ambiguous with empty regex
    # literal //. The RegexLiteral parse wins without Precedence semiring.

    # --- Ternary expression (structural only — branching) ---
    {
        my $tree = parse_concise('my $a = 1; my $b = 2; my $c = $a ? $b : 0;');
        ok(defined $tree, 'ternary expression parses');
        ok((grep { $_->name() eq 'cond_expr' } $tree->ops()->@*),
            'ternary has cond_expr op');
    }

    # --- PostfixIncDec (value context — avoids void context preinc optimization) ---
    {
        my $tree = parse_concise('my $a = 1; my $b = $a++;');
        ok(defined $tree, 'postfix increment parses');
        ok((grep { $_->name() eq 'postinc' } $tree->ops()->@*),
            'postfix increment has postinc op');
    }

    {
        my $tree = parse_concise('my $a = 1; my $b = $a--;');
        ok(defined $tree, 'postfix decrement parses');
        ok((grep { $_->name() eq 'postdec' } $tree->ops()->@*),
            'postfix decrement has postdec op');
    }

    # --- Compound assignment (structural only) ---
    # B::Concise uses the arithmetic op directly: $a += 2 → padsv, const, add
    {
        my $tree = parse_concise('my $a = 1; $a += 2;');
        ok(defined $tree, 'compound add-assign parses');
        ok((grep { $_->name() eq 'add' } $tree->ops()->@*),
            'compound += has add op');
    }

    {
        my $tree = parse_concise('my $a = 1; $a *= 3;');
        ok(defined $tree, 'compound multiply-assign parses');
        ok((grep { $_->name() eq 'multiply' } $tree->ops()->@*),
            'compound *= has multiply op');
    }

    # ========================================================================
    # Phase 4: Chained and nested expressions
    # ========================================================================

    # --- Chained binary: multiply then modulo (Precedence semiring disambiguates) ---
    # Uses * and % which have no unary counterparts (unlike + and -)
    # B::Concise: padsv, padsv, multiply, padsv, modulo, padsv_store
    {
        my $tree = parse_concise('my $a = 2; my $b = 3; my $c = 5; my $d = $a ** $b % $c;');
        ok(defined $tree, 'chained pow+modulo parses');
        my @ops = map { $_->name() } $tree->ops()->@*;
        ok((grep { $_ eq 'pow' } @ops), 'chained expr has pow op')
            or diag("ops: @ops");
        ok((grep { $_ eq 'modulo' } @ops), 'chained expr has modulo op')
            or diag("ops: @ops");
    }

    # --- Reversed precedence: modulo then pow (pow binds tighter) ---
    {
        my $tree = parse_concise('my $a = 2; my $b = 3; my $c = 5; my $d = $a % $b ** $c;');
        ok(defined $tree, 'reversed precedence modulo+pow parses');
        my @ops = map { $_->name() } $tree->ops()->@*;
        ok((grep { $_ eq 'pow' } @ops), 'reversed precedence has pow op')
            or diag("ops: @ops");
        ok((grep { $_ eq 'modulo' } @ops), 'reversed precedence has modulo op')
            or diag("ops: @ops");
    }

    # --- Ternary with comparison ---
    # B::Concise: padsv, padsv, gt, cond_expr, padsv, goto, padsv, padsv_store
    {
        my $tree = parse_concise('my $a = 1; my $b = 2; my $c = $a > $b ? $a : $b;');
        ok(defined $tree, 'ternary with comparison parses');
        my @ops = map { $_->name() } $tree->ops()->@*;
        ok((grep { $_ eq 'gt' } @ops), 'ternary+comparison has gt op');
        ok((grep { $_ eq 'cond_expr' } @ops), 'ternary+comparison has cond_expr op');
    }

    # --- Unary negation with binary modulo (% has no unary counterpart) ---
    {
        my $tree = parse_concise('my $a = 2; my $b = 3; my $c = -$a % $b;');
        ok(defined $tree, 'unary negation with modulo parses');
        my @ops = map { $_->name() } $tree->ops()->@*;
        ok((grep { $_ eq 'negate' } @ops), 'negate+modulo has negate op')
            or diag("ops: @ops");
        ok((grep { $_ eq 'modulo' } @ops), 'negate+modulo has modulo op')
            or diag("ops: @ops");
    }

    # --- Bitwise complement (untested unary operator) ---
    {
        my $tree = parse_concise('my $a = 5; my $b = ~$a;');
        ok(defined $tree, 'bitwise complement parses');
        ok((grep { $_->name() eq 'complement' } $tree->ops()->@*),
            'bitwise complement has complement op');
    }

    # --- Reference generation (untested unary operator) ---
    {
        my $tree = parse_concise('my $a = 1; my $b = \$a;');
        ok(defined $tree, 'reference generation parses');
        ok((grep { $_->name() eq 'srefgen' } $tree->ops()->@*),
            'reference generation has srefgen op');
    }
}

done_testing;
