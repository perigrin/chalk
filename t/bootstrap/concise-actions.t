# ABOUTME: Tests for ConciseTree::Actions that map Perl grammar rules to ConciseOps.
# ABOUTME: Tests Phase 2-5 (declarations, class/sub/method, expressions, control flow) via actual parsing.
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

    # --- Division (/ doesn't conflict with regex when followed by a number) ---
    {
        my $tree = parse_concise('my $a = 10; my $b = $a / 2;');
        ok(defined $tree, 'division expression parses');
        ok((grep { $_->name() eq 'divide' } $tree->ops()->@*),
            'division has divide op');
    }

    # --- Additional numeric comparison operators ---
    {
        my $tree = parse_concise('my $a = 1; my $b = 2; my $c = $a != $b;');
        ok(defined $tree, 'numeric inequality parses');
        ok((grep { $_->name() eq 'ne' } $tree->ops()->@*),
            'numeric inequality has ne op');
    }

    {
        my $tree = parse_concise('my $a = 1; my $b = 2; my $c = $a < $b;');
        ok(defined $tree, 'numeric less-than parses');
        ok((grep { $_->name() eq 'lt' } $tree->ops()->@*),
            'numeric less-than has lt op');
    }

    {
        my $tree = parse_concise('my $a = 1; my $b = 2; my $c = $a <= $b;');
        ok(defined $tree, 'numeric less-equal parses');
        ok((grep { $_->name() eq 'le' } $tree->ops()->@*),
            'numeric less-equal has le op');
    }

    {
        my $tree = parse_concise('my $a = 1; my $b = 2; my $c = $a >= $b;');
        ok(defined $tree, 'numeric greater-equal parses');
        ok((grep { $_->name() eq 'ge' } $tree->ops()->@*),
            'numeric greater-equal has ge op');
    }

    {
        my $tree = parse_concise('my $a = 1; my $b = 2; my $c = $a <=> $b;');
        ok(defined $tree, 'numeric spaceship parses');
        ok((grep { $_->name() eq 'ncmp' } $tree->ops()->@*),
            'numeric spaceship has ncmp op');
    }

    # --- String comparison operators ---
    {
        my $tree = parse_concise('my $a = "x"; my $b = "y"; my $c = $a ne $b;');
        ok(defined $tree, 'string ne parses');
        ok((grep { $_->name() eq 'sne' } $tree->ops()->@*),
            'string ne has sne op');
    }

    {
        my $tree = parse_concise('my $a = "x"; my $b = "y"; my $c = $a lt $b;');
        ok(defined $tree, 'string lt parses');
        ok((grep { $_->name() eq 'slt' } $tree->ops()->@*),
            'string lt has slt op');
    }

    {
        my $tree = parse_concise('my $a = "x"; my $b = "y"; my $c = $a gt $b;');
        ok(defined $tree, 'string gt parses');
        ok((grep { $_->name() eq 'sgt' } $tree->ops()->@*),
            'string gt has sgt op');
    }

    {
        my $tree = parse_concise('my $a = "x"; my $b = "y"; my $c = $a le $b;');
        ok(defined $tree, 'string le parses');
        ok((grep { $_->name() eq 'sle' } $tree->ops()->@*),
            'string le has sle op');
    }

    {
        my $tree = parse_concise('my $a = "x"; my $b = "y"; my $c = $a ge $b;');
        ok(defined $tree, 'string ge parses');
        ok((grep { $_->name() eq 'sge' } $tree->ops()->@*),
            'string ge has sge op');
    }

    {
        my $tree = parse_concise('my $a = "x"; my $b = "y"; my $c = $a cmp $b;');
        ok(defined $tree, 'string cmp parses');
        ok((grep { $_->name() eq 'scmp' } $tree->ops()->@*),
            'string cmp has scmp op');
    }

    # --- Bitwise operators ---
    {
        my $tree = parse_concise('my $a = 5; my $b = 3; my $c = $a & $b;');
        ok(defined $tree, 'bitwise AND parses');
        ok((grep { $_->name() eq 'bit_and' } $tree->ops()->@*),
            'bitwise AND has bit_and op');
    }

    {
        my $tree = parse_concise('my $a = 5; my $b = 3; my $c = $a | $b;');
        ok(defined $tree, 'bitwise OR parses');
        ok((grep { $_->name() eq 'bit_or' } $tree->ops()->@*),
            'bitwise OR has bit_or op');
    }

    {
        my $tree = parse_concise('my $a = 5; my $b = 3; my $c = $a ^ $b;');
        ok(defined $tree, 'bitwise XOR parses');
        ok((grep { $_->name() eq 'bit_xor' } $tree->ops()->@*),
            'bitwise XOR has bit_xor op');
    }

    # --- Shift operators ---
    {
        my $tree = parse_concise('my $a = 5; my $b = $a << 2;');
        ok(defined $tree, 'left shift parses');
        ok((grep { $_->name() eq 'left_shift' } $tree->ops()->@*),
            'left shift has left_shift op');
    }

    {
        my $tree = parse_concise('my $a = 20; my $b = $a >> 2;');
        ok(defined $tree, 'right shift parses');
        ok((grep { $_->name() eq 'right_shift' } $tree->ops()->@*),
            'right shift has right_shift op');
    }

    # --- Word-form logical operators ---
    {
        my $tree = parse_concise('my $a = 1; my $b = 2; my $c = $a xor $b;');
        ok(defined $tree, 'xor operator parses');
        ok((grep { $_->name() eq 'xor' } $tree->ops()->@*),
            'xor has xor op');
    }

    # --- Type check ---
    {
        my $tree = parse_concise('my $a = 1; my $c = $a isa "HASH";');
        ok(defined $tree, 'isa operator parses');
        ok((grep { $_->name() eq 'isa' } $tree->ops()->@*),
            'isa has isa op');
    }

    # --- String concatenation (structural only — Perl optimizes to multiconcat) ---
    {
        my $tree = parse_concise('my $a = "hello"; my $b = $a . "world";');
        ok(defined $tree, 'concatenation parses');
        ok((grep { $_->name() eq 'concat' } $tree->ops()->@*),
            'concatenation has concat op');
    }

    # --- Additional compound assignment operators ---
    {
        my $tree = parse_concise('my $a = 10; $a -= 3;');
        ok(defined $tree, 'compound -= parses');
        ok((grep { $_->name() eq 'subtract' } $tree->ops()->@*),
            'compound -= has subtract op');
    }

    {
        my $tree = parse_concise('my $a = 10; $a /= 2;');
        ok(defined $tree, 'compound /= parses');
        ok((grep { $_->name() eq 'divide' } $tree->ops()->@*),
            'compound /= has divide op');
    }

    {
        my $tree = parse_concise('my $a = 10; $a %= 3;');
        ok(defined $tree, 'compound %= parses');
        ok((grep { $_->name() eq 'modulo' } $tree->ops()->@*),
            'compound %= has modulo op');
    }

    {
        my $tree = parse_concise('my $a = 2; $a **= 3;');
        ok(defined $tree, 'compound **= parses');
        ok((grep { $_->name() eq 'pow' } $tree->ops()->@*),
            'compound **= has pow op');
    }

    {
        my $tree = parse_concise('my $a = "hello"; $a .= "world";');
        ok(defined $tree, 'compound .= parses');
        ok((grep { $_->name() eq 'concat' } $tree->ops()->@*),
            'compound .= has concat op');
    }

    {
        my $tree = parse_concise('my $a = 1; $a &&= 2;');
        ok(defined $tree, 'compound &&= parses');
        ok((grep { $_->name() eq 'and' } $tree->ops()->@*),
            'compound &&= has and op');
    }

    {
        my $tree = parse_concise('my $a = 0; $a ||= 1;');
        ok(defined $tree, 'compound ||= parses');
        ok((grep { $_->name() eq 'or' } $tree->ops()->@*),
            'compound ||= has or op');
    }

    {
        my $tree = parse_concise('my $a = 5; $a &= 3;');
        ok(defined $tree, 'compound &= parses');
        ok((grep { $_->name() eq 'bit_and' } $tree->ops()->@*),
            'compound &= has bit_and op');
    }

    {
        my $tree = parse_concise('my $a = 5; $a |= 3;');
        ok(defined $tree, 'compound |= parses');
        ok((grep { $_->name() eq 'bit_or' } $tree->ops()->@*),
            'compound |= has bit_or op');
    }

    {
        my $tree = parse_concise('my $a = 5; $a ^= 3;');
        ok(defined $tree, 'compound ^= parses');
        ok((grep { $_->name() eq 'bit_xor' } $tree->ops()->@*),
            'compound ^= has bit_xor op');
    }

    {
        my $tree = parse_concise('my $a = 5; $a <<= 2;');
        ok(defined $tree, 'compound <<= parses');
        ok((grep { $_->name() eq 'left_shift' } $tree->ops()->@*),
            'compound <<= has left_shift op');
    }

    {
        my $tree = parse_concise('my $a = 20; $a >>= 2;');
        ok(defined $tree, 'compound >>= parses');
        ok((grep { $_->name() eq 'right_shift' } $tree->ops()->@*),
            'compound >>= has right_shift op');
    }

    # --- Word-form logical operators (low-precedence equivalents of && || xor) ---
    {
        my $tree = parse_concise('my $a = 1; my $b = 2; my $c = $a and $b;');
        ok(defined $tree, 'word-form and parses');
        ok((grep { $_->name() eq 'and' } $tree->ops()->@*),
            'word-form and has and op');
    }

    {
        my $tree = parse_concise('my $a = 0; my $b = 2; my $c = $a or $b;');
        ok(defined $tree, 'word-form or parses');
        ok((grep { $_->name() eq 'or' } $tree->ops()->@*),
            'word-form or has or op');
    }

    # --- Range operators ---
    {
        my $tree = parse_concise('my $a = 1; my $b = 10; my $c = $a .. $b;');
        ok(defined $tree, 'range operator (..) parses');
        ok((grep { $_->name() eq 'range' } $tree->ops()->@*),
            'range (..) has range op');
    }

    {
        my $tree = parse_concise('my $a = 1; my $b = 10; my $c = $a ... $b;');
        ok(defined $tree, 'yada range operator (...) parses');
        ok((grep { $_->name() eq 'range' } $tree->ops()->@*),
            'yada range (...) has range op');
    }

    # --- Previously ambiguous operators (resolved by TypeInference) ---
    # Binary +: TypeInference rejects ambiguous unary + when BinaryOp scanned at same position
    {
        my $tree = parse_concise('my $a = 1; my $b = 2; my $c = $a + $b;');
        ok(defined $tree && (grep { $_->name() eq 'add' } $tree->ops()->@*),
            'binary addition has add op');
    }

    # Binary -: TypeInference rejects ambiguous unary - when BinaryOp scanned at same position
    {
        my $tree = parse_concise('my $a = 1; my $b = 2; my $c = $a - $b;');
        ok(defined $tree && (grep { $_->name() eq 'subtract' } $tree->ops()->@*),
            'binary subtraction has subtract op');
    }

    # Defined-or: TypeInference rejects empty regex // at scan time
    {
        my $tree = parse_concise('my $a = 0; my $b = 1; my $c = $a // $b;');
        ok(defined $tree && (grep { $_->name() eq 'dor' } $tree->ops()->@*),
            'defined-or has dor op');
    }

    # Compound //=: TypeInference rejects empty regex // at scan time
    {
        my $tree = parse_concise('my $a = 0; $a //= 1;');
        ok(defined $tree && (grep { $_->name() eq 'dor' } $tree->ops()->@*),
            'compound //= has dor op');
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

    # ========================================================================
    # Phase 5: Control flow
    # ========================================================================

    # --- IfStatement: if ($x) { $y; } → has 'and' op ---
    {
        my $tree = parse_concise('my $x = 1; my $y = 2; if ($x) { $y; }');
        ok(defined $tree, 'if statement parses');
        my @ops = map { $_->name() } $tree->ops()->@*;
        ok((grep { $_ eq 'and' } @ops), 'if statement has and op')
            or diag("ops: @ops");
    }

    # --- IfStatement: unless ($x) { $y; } → has 'or' op ---
    {
        my $tree = parse_concise('my $x = 0; my $y = 1; unless ($x) { $y; }');
        ok(defined $tree, 'unless statement parses');
        my @ops = map { $_->name() } $tree->ops()->@*;
        ok((grep { $_ eq 'or' } @ops), 'unless statement has or op')
            or diag("ops: @ops");
    }

    # --- IfStatement with else: if ($x) { $y; } else { $z; } → has 'cond_expr' ---
    {
        my $tree = parse_concise('my $x = 1; my $y = 2; my $z = 3; if ($x) { $y; } else { $z; }');
        ok(defined $tree, 'if-else statement parses');
        my @ops = map { $_->name() } $tree->ops()->@*;
        ok((grep { $_ eq 'cond_expr' } @ops), 'if-else has cond_expr op')
            or diag("ops: @ops");
    }

    # --- IfStatement with elsif: if ($a) { } elsif ($b) { } else { } → has cond_expr ops ---
    {
        my $tree = parse_concise('my $a = 1; my $b = 2; my $c = 3; if ($a) { $b; } elsif ($b) { $c; } else { $a; }');
        ok(defined $tree, 'if-elsif-else statement parses');
        my @ops = map { $_->name() } $tree->ops()->@*;
        my @cond_exprs = grep { $_ eq 'cond_expr' } @ops;
        ok(scalar @cond_exprs >= 1, 'if-elsif-else has cond_expr ops')
            or diag("ops: @ops");
    }

    # --- IfStatement: if without else, no child cond_expr → uses 'and' ---
    {
        my $tree = parse_concise('my $x = 1; if ($x) { my $y = 2; }');
        ok(defined $tree, 'if without else parses');
        my @ops = map { $_->name() } $tree->ops()->@*;
        ok((grep { $_ eq 'and' } @ops), 'if without else has and op')
            or diag("ops: @ops");
        ok(!(grep { $_ eq 'cond_expr' } @ops), 'if without else has no cond_expr')
            or diag("ops: @ops");
    }

    # --- IfStatement: unless without else → uses 'or' not 'cond_expr' ---
    {
        my $tree = parse_concise('my $x = 0; unless ($x) { my $y = 1; }');
        ok(defined $tree, 'unless without else parses');
        my @ops = map { $_->name() } $tree->ops()->@*;
        ok((grep { $_ eq 'or' } @ops), 'unless without else has or op')
            or diag("ops: @ops");
        ok(!(grep { $_ eq 'cond_expr' } @ops), 'unless without else has no cond_expr')
            or diag("ops: @ops");
    }

    # --- IfStatement: unless with else → uses 'cond_expr' ---
    {
        my $tree = parse_concise('my $x = 0; my $y = 1; unless ($x) { $y; } else { $x; }');
        ok(defined $tree, 'unless-else statement parses');
        my @ops = map { $_->name() } $tree->ops()->@*;
        ok((grep { $_ eq 'cond_expr' } @ops), 'unless-else has cond_expr op')
            or diag("ops: @ops");
    }

    # --- WhileStatement: while ($x) { $y; } → enterloop, and, unstack, leaveloop ---
    {
        my $tree = parse_concise('my $x = 1; my $y = 2; while ($x) { $y; }');
        ok(defined $tree, 'while statement parses');
        my @ops = map { $_->name() } $tree->ops()->@*;
        ok((grep { $_ eq 'enterloop' } @ops), 'while has enterloop op')
            or diag("ops: @ops");
        ok((grep { $_ eq 'and' } @ops), 'while has and op')
            or diag("ops: @ops");
        ok((grep { $_ eq 'unstack' } @ops), 'while has unstack op')
            or diag("ops: @ops");
        ok((grep { $_ eq 'leaveloop' } @ops), 'while has leaveloop op')
            or diag("ops: @ops");
    }

    # --- WhileStatement: until ($x) { $y; } → enterloop, or, unstack, leaveloop ---
    {
        my $tree = parse_concise('my $x = 0; my $y = 1; until ($x) { $y; }');
        ok(defined $tree, 'until statement parses');
        my @ops = map { $_->name() } $tree->ops()->@*;
        ok((grep { $_ eq 'enterloop' } @ops), 'until has enterloop op')
            or diag("ops: @ops");
        ok((grep { $_ eq 'or' } @ops), 'until has or op')
            or diag("ops: @ops");
        ok((grep { $_ eq 'unstack' } @ops), 'until has unstack op')
            or diag("ops: @ops");
        ok((grep { $_ eq 'leaveloop' } @ops), 'until has leaveloop op')
            or diag("ops: @ops");
    }

    # --- ForStatement (C-style): for ($i = 0; $i < 10; $i++) { } ---
    # Grammar uses Expression? in init position; my-declarations are not Expressions.
    {
        my $tree = parse_concise('my $i = 0; for ($i = 0; $i < 10; $i++) { my $x = 1; }');
        ok(defined $tree, 'C-style for statement parses');
        my @ops = map { $_->name() } $tree->ops()->@*;
        ok((grep { $_ eq 'enterloop' } @ops), 'C-style for has enterloop op')
            or diag("ops: @ops");
        ok((grep { $_ eq 'leaveloop' } @ops), 'C-style for has leaveloop op')
            or diag("ops: @ops");
    }

    # --- ForStatement (infinite): for (;;) { $x; } ---
    {
        my $tree = parse_concise('my $x = 1; for (;;) { $x; }');
        ok(defined $tree, 'infinite for statement parses');
        my @ops = map { $_->name() } $tree->ops()->@*;
        ok((grep { $_ eq 'enterloop' } @ops), 'infinite for has enterloop op')
            or diag("ops: @ops");
        ok((grep { $_ eq 'leaveloop' } @ops), 'infinite for has leaveloop op')
            or diag("ops: @ops");
    }

    # --- ForStatement (condition only): for (; $x;) { } ---
    {
        my $tree = parse_concise('my $x = 1; for (; $x;) { $x; }');
        ok(defined $tree, 'for with condition only parses');
        my @ops = map { $_->name() } $tree->ops()->@*;
        ok((grep { $_ eq 'enterloop' } @ops), 'for condition-only has enterloop op')
            or diag("ops: @ops");
        ok((grep { $_ eq 'and' } @ops), 'for condition-only has and op')
            or diag("ops: @ops");
        ok((grep { $_ eq 'leaveloop' } @ops), 'for condition-only has leaveloop op')
            or diag("ops: @ops");
    }

    # --- ForeachStatement: for my $i (@list) { $i; } ---
    {
        my $tree = parse_concise('my @list = (1, 2, 3); for my $i (@list) { $i; }');
        ok(defined $tree, 'foreach statement parses');
        my @ops = map { $_->name() } $tree->ops()->@*;
        ok((grep { $_ eq 'enteriter' } @ops), 'foreach has enteriter op')
            or diag("ops: @ops");
        ok((grep { $_ eq 'iter' } @ops), 'foreach has iter op')
            or diag("ops: @ops");
        ok((grep { $_ eq 'and' } @ops), 'foreach has and op')
            or diag("ops: @ops");
        ok((grep { $_ eq 'unstack' } @ops), 'foreach has unstack op')
            or diag("ops: @ops");
        ok((grep { $_ eq 'leaveloop' } @ops), 'foreach has leaveloop op')
            or diag("ops: @ops");
    }

    # --- ForeachStatement (no variable): for (@list) { $x; } ---
    # Without explicit iterator variable, perl uses $_
    {
        my $tree = parse_concise('my @list = (1, 2, 3); my $x = 0; for my $item (@list) { $x; }');
        ok(defined $tree, 'foreach with variable parses');
        my @ops = map { $_->name() } $tree->ops()->@*;
        ok((grep { $_ eq 'enteriter' } @ops), 'foreach with var has enteriter op')
            or diag("ops: @ops");
        ok((grep { $_ eq 'leaveloop' } @ops), 'foreach with var has leaveloop op')
            or diag("ops: @ops");
    }
}

done_testing;
