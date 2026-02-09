# ABOUTME: Semantic actions that map Perl grammar rules to ConciseOp sequences.
# ABOUTME: Produces post-optimization-equivalent ops matching perl -MO=Concise,-exec output.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::ConciseOp;
use Chalk::Bootstrap::ConciseTree;

class Chalk::Bootstrap::ConciseTree::Actions {

    # Helper: create a bare ConciseOp without wrapping in a ConciseTree
    my sub _make_op($name, $arity, %opts) {
        return Chalk::Bootstrap::ConciseOp->new(
            name      => $name,
            arity     => $arity,
            type_info => $opts{type_info},
            private   => $opts{private} // '',
        );
    }

    # Helper: create a single-op ConciseTree
    my sub _op($name, $arity, %opts) {
        my $tree = Chalk::Bootstrap::ConciseTree->new();
        $tree->push_op(_make_op($name, $arity, %opts));
        return $tree;
    }

    # Helper: collect all ConciseTree values from context leaves
    my sub _collect_trees($ctx) {
        my @trees;
        for my $leaf ($ctx->leaves()) {
            my $focus = $leaf->extract();
            if (defined $focus && $focus isa Chalk::Bootstrap::ConciseTree) {
                push @trees, $focus;
            }
        }
        return @trees;
    }

    # Helper: collect ALL leaf items in order (both ConciseTree and text),
    # needed for fat comma detection where text tokens like '=>' matter.
    my sub _collect_items($ctx) {
        my @items;
        my $focus = $ctx->extract();
        if (defined $focus && $focus isa Chalk::Bootstrap::ConciseTree) {
            push @items, { type => 'tree', value => $focus, ctx => $ctx };
            return @items;
        }
        if (defined $focus && !ref($focus)) {
            push @items, { type => 'text', value => $focus, ctx => $ctx };
            return @items;
        }
        # Recurse into children
        for my $child ($ctx->children()->@*) {
            push @items, __SUB__->($child);
        }
        return @items;
    }

    # Helper: concatenate all child trees into one, filtering out empty trees
    my sub _merge_trees(@trees) {
        my $result = Chalk::Bootstrap::ConciseTree->new();
        for my $tree (@trees) {
            $result->concat($tree) if $tree->op_count() > 0;
        }
        return $result;
    }

    # Helper: find first op with a given name in a list of trees
    my sub _find_op_in_trees($name, @trees) {
        for my $tree (@trees) {
            for my $op ($tree->ops()->@*) {
                return $op if $op->name() eq $name;
            }
        }
        return undef;
    }

    # Helper: check if any child tree contains an op with the given name
    my sub _has_op($name, @trees) {
        return defined _find_op_in_trees($name, @trees);
    }

    # Helper: walk context tree to find a text leaf matching an operator in the given map.
    # Descends through empty ConciseTree nodes (from BinaryOp/UnaryOp/AssignOp actions)
    # to find the underlying scanned text. Stops at non-empty ConciseTree focuses
    # to avoid finding operators from nested BinaryExpressions in chained expressions.
    my sub _extract_operator_text($ctx, $op_map) {
        my $focus = $ctx->extract();
        # Text leaf: check if it's a known operator
        if (defined $focus && !ref($focus)) {
            my $v = $focus;
            $v =~ s/^\s+|\s+$//g;
            return $v if exists $op_map->{$v};
        }
        # Non-empty ConciseTree: this is a processed Expression result — don't descend
        # into its children, which may contain operators from inner BinaryExpressions.
        # Empty ConciseTrees (from BinaryOp/AssignOp) are transparent markers we
        # need to descend through.
        if (defined $focus && $focus isa Chalk::Bootstrap::ConciseTree
                && $focus->op_count() > 0) {
            return undef;
        }
        # Recurse into children (including through empty ConciseTrees)
        for my $child ($ctx->children()->@*) {
            my $found = __SUB__->($child, $op_map);
            return $found if defined $found;
        }
        return undef;
    }

    # Operator → B::Concise op name mapping for binary expressions
    my %OP_MAP = (
        # Arithmetic (§15)
        '+'   => 'add',       '-'   => 'subtract',
        '*'   => 'multiply',  '/'   => 'divide',
        '%'   => 'modulo',    '**'  => 'pow',
        'x'   => 'repeat',
        # String
        '.'   => 'concat',
        # Comparison numeric
        '=='  => 'eq',        '!='  => 'ne',
        '<'   => 'lt',        '>'   => 'gt',
        '<='  => 'le',        '>='  => 'ge',
        '<=>' => 'ncmp',
        # Comparison string
        'eq'  => 'seq',       'ne'  => 'sne',
        'lt'  => 'slt',       'gt'  => 'sgt',
        'le'  => 'sle',       'ge'  => 'sge',
        'cmp' => 'scmp',
        # Logical (short-circuit)
        '&&'  => 'and',       '||'  => 'or',
        '//'  => 'dor',
        'and' => 'and',       'or'  => 'or',
        'xor' => 'xor',
        # Bitwise
        '&'   => 'bit_and',   '|'   => 'bit_or',
        '^'   => 'bit_xor',
        # Shift
        '<<'  => 'left_shift', '>>' => 'right_shift',
        # Regex binding: =~ and !~ are transparent — the regex op on the RHS
        # (match/subst from RegexLiteral action) handles the binding.
        # B::Concise does not produce a separate regcomp op for these.
        # Range
        '..'  => 'range',     '...' => 'range',
        # Type check
        'isa' => 'isa',
    );

    # Unary operator → op name
    my %UNARY_OP_MAP = (
        '-'   => 'negate',
        '!'   => 'not',
        '+'   => 'null',       # unary + is a no-op in B::Concise
        '~'   => 'complement',
        '\\'  => 'srefgen',
        'not' => 'not',
    );

    # Compound assign: map operator text to arithmetic op name
    my %ASSIGN_OP_MAP = (
        '+='   => 'add',      '-='   => 'subtract',
        '*='   => 'multiply',  '/='   => 'divide',
        '%='   => 'modulo',   '**='  => 'pow',
        '.='   => 'concat',
        '&&='  => 'and',      '||='  => 'or',
        '//='  => 'dor',
        '&='   => 'bit_and',  '|='   => 'bit_or',
        '^='   => 'bit_xor',
        '<<='  => 'left_shift', '>>=' => 'right_shift',
    );

    # Short-circuit ops use branching arity '|'
    my %BRANCHING_OPS = map { $_ => true } qw(and or dor);

    # Remove consecutive duplicate nextstate ops (artifact of ambiguous add())
    my sub _dedup_nextstates($tree) {
        my @ops = $tree->ops()->@*;
        my @deduped;
        my $prev_was_nextstate = false;
        for my $op (@ops) {
            if ($op->name() eq 'nextstate') {
                if (!$prev_was_nextstate) {
                    push @deduped, $op;
                }
                $prev_was_nextstate = true;
            } else {
                push @deduped, $op;
                $prev_was_nextstate = false;
            }
        }
        # Also remove trailing nextstate (before leave)
        if (@deduped && $deduped[-1]->name() eq 'nextstate') {
            pop @deduped;
        }
        return Chalk::Bootstrap::ConciseTree->new(ops => \@deduped);
    }

    # Peephole optimizer for variable declaration patterns.
    # Recognizes pad+expr combinations and emits proper B::Concise patterns.
    my sub _peephole_vardecl($tree) {
        my @ops = $tree->ops()->@*;
        return $tree unless @ops >= 1;

        # Find pad op (padsv/padav/padhv) and classify
        my $pad_idx = undef;
        my $pad_op = undef;
        for my $i (0 .. $#ops) {
            if ($ops[$i]->name() =~ /^(padsv|padav|padhv)$/) {
                $pad_idx = $i;
                $pad_op = $ops[$i];
                last;
            }
        }
        return $tree unless defined $pad_op;

        # Collect expression ops (everything that's not the pad op)
        my @expr_ops;
        for my $i (0 .. $#ops) {
            push @expr_ops, $ops[$i] unless $i == $pad_idx;
        }

        my $has_init = scalar @expr_ops > 0;
        my $pad_name = $pad_op->name();

        # Skip peephole for compound assignment: $a += 2 → padsv, const, add.
        # AssignmentExpression marks compound assign ops with /COMPOUND private flag.
        if ($has_init && $expr_ops[-1]->private() =~ m{/COMPOUND}) {
            return $tree;
        }

        if ($pad_name eq 'padsv' && $has_init) {
            # Scalar with initializer: expr_ops + padsv_store/LVINTRO
            my $result = Chalk::Bootstrap::ConciseTree->new();
            for my $op (@expr_ops) {
                $result->push_op($op);
            }
            $result->push_op(Chalk::Bootstrap::ConciseOp->new(
                name      => 'padsv_store',
                arity     => '1',
                type_info => $pad_op->type_info(),
                private   => '/LVINTRO',
            ));
            return $result;
        }

        if (($pad_name eq 'padav' || $pad_name eq 'padhv') && $has_init) {
            # Array/hash with initializer:
            # pushmark + expr_ops + pushmark + pad/LVINTRO + aassign
            my $result = Chalk::Bootstrap::ConciseTree->new();
            $result->push_op(Chalk::Bootstrap::ConciseOp->new(
                name => 'pushmark', arity => '0',
            ));
            for my $op (@expr_ops) {
                $result->push_op($op);
            }
            $result->push_op(Chalk::Bootstrap::ConciseOp->new(
                name => 'pushmark', arity => '0',
            ));
            $result->push_op(Chalk::Bootstrap::ConciseOp->new(
                name    => $pad_name,
                arity   => '0',
                type_info => $pad_op->type_info(),
                private => '/LVINTRO',
            ));
            $result->push_op(Chalk::Bootstrap::ConciseOp->new(
                name => 'aassign', arity => '2',
            ));
            return $result;
        }

        # Bare declaration: add /LVINTRO to the pad op
        if (!$has_init) {
            return _op($pad_name, '0',
                type_info => $pad_op->type_info(),
                private   => '/LVINTRO',
            );
        }

        return $tree;
    }

    # §2 Program ::= _ StatementList? _
    # Wraps everything in enter/leave envelope.
    # Deduplicates consecutive nextstates (artifact of ambiguous grammar's add()).
    method Program($ctx) {
        my @child_trees = _collect_trees($ctx);
        my $body = _merge_trees(@child_trees);

        # Deduplicate consecutive nextstates
        my $clean = _dedup_nextstates($body);

        my $result = Chalk::Bootstrap::ConciseTree->new();
        $result->push_op(Chalk::Bootstrap::ConciseOp->new(
            name => 'enter', arity => '0',
        ));

        # Check if the program has any runtime ops (non-nextstate)
        my $has_runtime_ops = false;
        for my $op ($clean->ops()->@*) {
            if ($op->name() ne 'nextstate') {
                $has_runtime_ops = true;
                last;
            }
        }

        if ($has_runtime_ops) {
            $result->concat($clean);
        } else {
            # Compile-time only programs get a stub
            $result->push_op(Chalk::Bootstrap::ConciseOp->new(
                name => 'stub', arity => '0',
            ));
        }

        $result->push_op(Chalk::Bootstrap::ConciseOp->new(
            name => 'leave', arity => '@',
        ));
        return $result;
    }

    # §2 StatementList — transparent pass-through (nextstates added by StatementItem)
    # StatementList ::= StatementItem | StatementList _ StatementItem
    method StatementList($ctx) {
        my @child_trees = _collect_trees($ctx);
        return _merge_trees(@child_trees);
    }

    # §2 StatementItem — prepend nextstate, then peephole-optimize child ops.
    # Peephole patterns:
    #   padsv + const → const + padsv_store (scalar init)
    #   padav/padhv + const... → pushmark + const... + pushmark + pad/LVINTRO + aassign (list init)
    method StatementItem($ctx) {
        my @trees = _collect_trees($ctx);
        my $body = _merge_trees(@trees);
        my $optimized = _peephole_vardecl($body);

        my $result = Chalk::Bootstrap::ConciseTree->new();
        $result->push_op(Chalk::Bootstrap::ConciseOp->new(
            name => 'nextstate', arity => ';',
        ));
        $result->concat($optimized) if $optimized->op_count() > 0;
        return $result;
    }

    # §3 SimpleStatement — transparent pass-through
    method SimpleStatement($ctx) {
        my @trees = _collect_trees($ctx);
        return _merge_trees(@trees);
    }

    # §4 ExpressionStatement — transparent pass-through
    method ExpressionStatement($ctx) {
        my @trees = _collect_trees($ctx);
        return _merge_trees(@trees);
    }

    # §12 Expression — transparent pass-through
    method Expression($ctx) {
        my @trees = _collect_trees($ctx);
        return _merge_trees(@trees);
    }

    # §12 ExpressionList — collect all expressions.
    # Detects fat comma (=>) and auto-quotes LHS bare identifiers as const[PV]/BARE.
    method ExpressionList($ctx) {
        my @items = _collect_items($ctx);

        # Check if any text item is a fat comma
        my $has_fat_comma = false;
        for my $item (@items) {
            if ($item->{type} eq 'text' && $item->{value} =~ /^=>$/) {
                $has_fat_comma = true;
                last;
            }
        }

        unless ($has_fat_comma) {
            # No fat comma — fall through to standard tree merge
            my @trees = _collect_trees($ctx);
            return _merge_trees(@trees);
        }

        # Fat comma path: iterate items, auto-quote empty trees before =>
        my $result = Chalk::Bootstrap::ConciseTree->new();
        for my $i (0 .. $#items) {
            my $item = $items[$i];
            if ($item->{type} eq 'text') {
                # Skip whitespace and operator text (=>, ,)
                next;
            }
            # It's a tree item
            my $tree = $item->{value};

            # Check if the next non-whitespace text item is =>
            my $before_fat_comma = false;
            for my $j ($i + 1 .. $#items) {
                my $next = $items[$j];
                if ($next->{type} eq 'text') {
                    if ($next->{value} =~ /^=>$/) {
                        $before_fat_comma = true;
                    }
                    last if $next->{value} =~ /\S/;
                }
                last if $next->{type} eq 'tree';
            }

            if ($before_fat_comma && $tree->op_count() == 0) {
                # Empty tree from bare identifier before =>
                my $ident_text = $item->{ctx}->scanned_text();
                $ident_text =~ s/^\s+|\s+$//g;
                if (length $ident_text) {
                    $result->push_op(Chalk::Bootstrap::ConciseOp->new(
                        name      => 'const',
                        arity     => '$',
                        type_info => qq{PV "$ident_text"},
                        private   => '/BARE',
                    ));
                }
            } elsif ($before_fat_comma && $tree->op_count() > 0) {
                # Non-empty tree before => — the tree is from a recursive
                # ExpressionList that may have lost a trailing bare identifier.
                # Check if scanned text ends with a bare identifier after comma.
                $result->concat($tree);
                my $scanned = $item->{ctx}->scanned_text();
                if ($scanned =~ /,\s*([a-zA-Z_]\w*)\s*$/) {
                    my $trailing_ident = $1;
                    $result->push_op(Chalk::Bootstrap::ConciseOp->new(
                        name      => 'const',
                        arity     => '$',
                        type_info => qq{PV "$trailing_ident"},
                        private   => '/BARE',
                    ));
                }
            } elsif ($tree->op_count() > 0) {
                $result->concat($tree);
            }
        }
        return $result;
    }

    # §13 Atom — transparent pass-through
    method Atom($ctx) {
        my @trees = _collect_trees($ctx);
        return _merge_trees(@trees);
    }

    # §13 ParenExpr — transparent pass-through
    method ParenExpr($ctx) {
        my @trees = _collect_trees($ctx);
        return _merge_trees(@trees);
    }

    # §15 BinaryOp — extract operator text, return empty tree
    method BinaryOp($ctx) {
        return Chalk::Bootstrap::ConciseTree->new();
    }

    # §15 BinaryExpression — operand op operand → child ops + arithmetic op
    # Finds operator via _extract_operator_text which walks the context tree
    # looking for text leaves that match known operators.
    method BinaryExpression($ctx) {
        my $op_text = _extract_operator_text($ctx, \%OP_MAP);
        my @trees = _collect_trees($ctx);
        my $result = _merge_trees(@trees);
        if (defined $op_text && exists $OP_MAP{$op_text}) {
            my $op_name = $OP_MAP{$op_text};
            my $arity = $BRANCHING_OPS{$op_name} ? '|' : '2';
            $result->push_op(_make_op($op_name, $arity));
        }
        return $result;
    }

    # §14 UnaryExpression — prefix operator + expression → child ops + unary op
    method UnaryExpression($ctx) {
        my $op_text = _extract_operator_text($ctx, \%UNARY_OP_MAP);
        my @trees = _collect_trees($ctx);
        my $result = _merge_trees(@trees);
        if (defined $op_text && exists $UNARY_OP_MAP{$op_text}) {
            $result->push_op(_make_op($UNARY_OP_MAP{$op_text}, '1'));
        }
        return $result;
    }

    # §16 TernaryExpression — condition ? then : else → child ops + cond_expr
    # B::Concise interleaves branches; our flat model appends cond_expr at end.
    method TernaryExpression($ctx) {
        my @trees = _collect_trees($ctx);
        my $result = _merge_trees(@trees);
        $result->push_op(_make_op('cond_expr', '|'));
        return $result;
    }

    # §16 PostfixIncDec — expression++ or expression-- → child ops + postinc/postdec
    method PostfixIncDec($ctx) {
        my $is_dec = false;
        my $scanned = $ctx->scanned_text();
        if (defined $scanned && $scanned =~ /--/) {
            $is_dec = true;
        }
        my @trees = _collect_trees($ctx);
        my $result = _merge_trees(@trees);
        my $op_name = $is_dec ? 'postdec' : 'postinc';
        $result->push_op(_make_op($op_name, '1'));
        return $result;
    }

    # §16 PostfixExpression — transparent pass-through
    method PostfixExpression($ctx) {
        my @trees = _collect_trees($ctx);
        return _merge_trees(@trees);
    }

    # §7 UseDeclaration — compile-time only, produces empty tree
    method UseDeclaration($ctx) {
        return Chalk::Bootstrap::ConciseTree->new();
    }

    # §7 ModuleName — transparent (no runtime ops)
    method ModuleName($ctx) {
        return Chalk::Bootstrap::ConciseTree->new();
    }

    # §7 ImportList — transparent (no runtime ops)
    method ImportList($ctx) {
        return Chalk::Bootstrap::ConciseTree->new();
    }

    # §8 VariableDeclaration — transparent pass-through.
    # The grammar is ambiguous between bare and initialized forms; both may
    # complete and add() picks one. The peephole optimizer at StatementItem
    # level handles combining pad ops with initializers.
    method VariableDeclaration($ctx) {
        my @child_trees = _collect_trees($ctx);
        return _merge_trees(@child_trees);
    }

    # §8 VariableList — transparent
    method VariableList($ctx) {
        my @trees = _collect_trees($ctx);
        return _merge_trees(@trees);
    }

    # §19 Literal — transparent pass-through
    method Literal($ctx) {
        my @trees = _collect_trees($ctx);
        return _merge_trees(@trees);
    }

    # §19 NumericLiteral — const[IV N] or const[NV N]
    method NumericLiteral($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;

        # Determine type: float → NV, integer → IV
        my ($type, $value);
        if ($text =~ /\./ || $text =~ /[eE]/) {
            $type = 'NV';
            $value = $text;
        } elsif ($text =~ /^0[xX]/) {
            $type = 'IV';
            # Convert hex to decimal for consistency with B::Concise
            $value = oct($text);
        } elsif ($text =~ /^0[bB]/) {
            $type = 'IV';
            $value = oct($text);
        } elsif ($text =~ /^0[oO]/) {
            $type = 'IV';
            $value = oct($text);
        } else {
            $type = 'IV';
            $value = $text;
            $value =~ s/_//g;  # Strip numeric separators
        }

        return _op('const', '$', type_info => "$type $value");
    }

    # §19 StringLiteral — const[PV "..."]
    method StringLiteral($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;

        # Extract the string content (strip delimiters)
        my $content;
        if ($text =~ /^'(.*)'$/s) {
            $content = $1;
        } elsif ($text =~ /^"(.*)"$/s) {
            $content = $1;
        } elsif ($text =~ /^qq?\s*\{(.*)\}$/s) {
            $content = $1;
        } elsif ($text =~ /^qq?\s*\[(.*)\]$/s) {
            $content = $1;
        } else {
            $content = $text;
        }

        return _op('const', '$', type_info => qq{PV "$content"});
    }

    # §19 RegexLiteral — match, qr, or subst ops with regex arity
    method RegexLiteral($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;

        # s/pattern/replacement/flags or s{pattern}{replacement}flags
        # Uses escape-aware character class to handle \/ in patterns
        if ($text =~ m{^s\s*/((?:[^/\\]|\\.)*?)/((?:[^/\\]|\\.)*)/([msixpodualngcer]*)$}s) {
            my ($pattern, $replacement) = ($1, $2);
            my $result = Chalk::Bootstrap::ConciseTree->new();
            $result->push_op(Chalk::Bootstrap::ConciseOp->new(
                name      => 'const',
                arity     => '$',
                type_info => qq{PV "$replacement"},
            ));
            $result->push_op(Chalk::Bootstrap::ConciseOp->new(
                name      => 'subst',
                arity     => '/',
                type_info => qq{/"$pattern"/},
            ));
            return $result;
        }
        if ($text =~ m{^s\s*\{(.+?)\}\s*\{(.*?)\}([msixpodualngcer]*)$}s) {
            my ($pattern, $replacement) = ($1, $2);
            my $result = Chalk::Bootstrap::ConciseTree->new();
            $result->push_op(Chalk::Bootstrap::ConciseOp->new(
                name      => 'const',
                arity     => '$',
                type_info => qq{PV "$replacement"},
            ));
            $result->push_op(Chalk::Bootstrap::ConciseOp->new(
                name      => 'subst',
                arity     => '/',
                type_info => qq{/"$pattern"/},
            ));
            return $result;
        }

        # qr/pattern/flags — escape-aware
        if ($text =~ m{^qr\s*/((?:[^/\\]|\\.)*)/([msixpodualngcer]*)$}s) {
            my $pattern = $1;
            return _op('qr', '/', type_info => qq{/"$pattern"/});
        }

        # m/pattern/flags or m{pattern}flags — escape-aware
        if ($text =~ m{^m\s*/((?:[^/\\]|\\.)*)/([msixpodualngcer]*)$}s) {
            my $pattern = $1;
            return _op('match', '/', type_info => qq{/"$pattern"/});
        }
        if ($text =~ m{^m\s*\{(.+?)\}([msixpodualngcer]*)$}s) {
            my $pattern = $1;
            return _op('match', '/', type_info => qq{/"$pattern"/});
        }

        # bare /pattern/flags — escape-aware
        if ($text =~ m{^/((?:[^/\\]|\\.)*)/([msixpodualngcer]*)$}s) {
            my $pattern = $1;
            return _op('match', '/', type_info => qq{/"$pattern"/});
        }

        # Fallback: empty tree
        return Chalk::Bootstrap::ConciseTree->new();
    }

    # §18 Variable — transparent pass-through
    method Variable($ctx) {
        my @trees = _collect_trees($ctx);
        return @trees ? _merge_trees(@trees) : Chalk::Bootstrap::ConciseTree->new();
    }

    # §18 ScalarVariable — padsv[$name]
    method ScalarVariable($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return _op('padsv', '0', type_info => $text);
    }

    # §18 ArrayVariable — padav[@name]
    method ArrayVariable($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return _op('padav', '0', type_info => $text);
    }

    # §18 HashVariable — padhv[%name]
    method HashVariable($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return _op('padhv', '0', type_info => $text);
    }

    # §20 Identifier — no runtime ops (identifiers are resolved elsewhere)
    method Identifier($ctx) {
        return Chalk::Bootstrap::ConciseTree->new();
    }

    # §20 QualifiedIdentifier — no runtime ops
    method QualifiedIdentifier($ctx) {
        return Chalk::Bootstrap::ConciseTree->new();
    }

    # §20 Version — no runtime ops (compile-time only)
    method Version($ctx) {
        return Chalk::Bootstrap::ConciseTree->new();
    }

    # §8 FieldDeclaration — similar to VariableDeclaration
    method FieldDeclaration($ctx) {
        my @child_trees = _collect_trees($ctx);
        my $var_op = undef;

        for my $tree (@child_trees) {
            my $first_op = $tree->ops()->[0];
            if (defined $first_op && $first_op->name() =~ /^(padsv|padav|padhv)$/) {
                $var_op = $first_op;
                last;
            }
        }

        if (defined $var_op) {
            return _op($var_op->name(), '0',
                type_info => $var_op->type_info(),
                private   => '/LVINTRO',
            );
        }

        return _merge_trees(@child_trees);
    }

    # §8 DefaultValue — transparent
    method DefaultValue($ctx) {
        my @trees = _collect_trees($ctx);
        return _merge_trees(@trees);
    }

    # §17 AssignOp — extract operator text, return empty tree
    method AssignOp($ctx) {
        return Chalk::Bootstrap::ConciseTree->new();
    }

    # §17 AssignmentExpression — transparent for plain '=', emits arithmetic op for compound assign.
    # B::Concise uses the arithmetic op directly: $a += 2 → padsv, const, add (not sassign).
    # The arithmetic op gets /COMPOUND private flag so the peephole optimizer knows
    # not to convert the padsv into a padsv_store.
    method AssignmentExpression($ctx) {
        my $assign_text = _extract_operator_text($ctx, \%ASSIGN_OP_MAP);
        my @trees = _collect_trees($ctx);
        my $result = _merge_trees(@trees);
        if (defined $assign_text) {
            my $op_name = $ASSIGN_OP_MAP{$assign_text};
            my $arity = $BRANCHING_OPS{$op_name} ? '|' : '2';
            $result->push_op(_make_op($op_name, $arity, private => '/COMPOUND'));
        }
        return $result;
    }

    # §3 CompoundStatement — transparent pass-through
    method CompoundStatement($ctx) {
        my @trees = _collect_trees($ctx);
        return _merge_trees(@trees);
    }

    # §20 Block — transparent pass-through (children are statement ops)
    method Block($ctx) {
        my @trees = _collect_trees($ctx);
        return _merge_trees(@trees);
    }

    # §9 SubroutineDefinition — compile-time only; body ops belong to the sub's pad
    method SubroutineDefinition($ctx) {
        return Chalk::Bootstrap::ConciseTree->new();
    }

    # §9 ClassBlock — compile-time only; class body compiled at compile time
    method ClassBlock($ctx) {
        return Chalk::Bootstrap::ConciseTree->new();
    }

    # §10 MethodDefinition — compile-time only; inside class block
    method MethodDefinition($ctx) {
        return Chalk::Bootstrap::ConciseTree->new();
    }

    # §10 AdjustBlock — compile-time only; inside class block
    method AdjustBlock($ctx) {
        return Chalk::Bootstrap::ConciseTree->new();
    }

    # §10 AttributeList — no runtime ops
    method AttributeList($ctx) {
        return Chalk::Bootstrap::ConciseTree->new();
    }

    # §10 Attribute — no runtime ops
    method Attribute($ctx) {
        return Chalk::Bootstrap::ConciseTree->new();
    }

    # §11 Signature — no runtime ops at definition site
    method Signature($ctx) {
        return Chalk::Bootstrap::ConciseTree->new();
    }

    # §11 SignatureParams — no runtime ops
    method SignatureParams($ctx) {
        return Chalk::Bootstrap::ConciseTree->new();
    }

    # §11 SignatureParam — no runtime ops
    method SignatureParam($ctx) {
        return Chalk::Bootstrap::ConciseTree->new();
    }

    # §11 ScalarSignatureParam — no runtime ops
    method ScalarSignatureParam($ctx) {
        return Chalk::Bootstrap::ConciseTree->new();
    }

    # §11 SlurpySignatureParam — no runtime ops
    method SlurpySignatureParam($ctx) {
        return Chalk::Bootstrap::ConciseTree->new();
    }

    # §13 AnonymousSub — produces anoncode[CV CODE] at runtime
    method AnonymousSub($ctx) {
        return _op('anoncode', '$', type_info => 'CV CODE');
    }

    # §5 IfStatement — if/unless with optional elsif/else
    # Simple if → and, simple unless → or, with else/elsif → cond_expr
    method IfStatement($ctx) {
        my $scanned = $ctx->scanned_text();
        my $is_unless = (defined $scanned && $scanned =~ /\bunless\b/);
        my @trees = _collect_trees($ctx);
        my $result = _merge_trees(@trees);

        # Determine branching op based on else/elsif presence
        my $has_else = _has_op('cond_expr', @trees);
        if ($has_else || scalar @trees > 2) {
            $result->push_op(_make_op('cond_expr', '|'));
        } elsif ($is_unless) {
            $result->push_op(_make_op('or', '|'));
        } else {
            $result->push_op(_make_op('and', '|'));
        }
        return $result;
    }

    # §6 WhileStatement — while/until loop with enterloop/leaveloop envelope
    method WhileStatement($ctx) {
        my $scanned = $ctx->scanned_text();
        my $is_until = (defined $scanned && $scanned =~ /\buntil\b/);
        my @trees = _collect_trees($ctx);

        my $result = Chalk::Bootstrap::ConciseTree->new();
        $result->push_op(_make_op('enterloop', '{'));
        $result->concat(_merge_trees(@trees));
        my $branch_op = $is_until ? 'or' : 'and';
        $result->push_op(_make_op($branch_op, '|'));
        $result->push_op(_make_op('unstack', '0'));
        $result->push_op(_make_op('leaveloop', '2'));
        return $result;
    }

    # §6 ForInit — transparent pass-through (init slot of C-style for loop)
    method ForInit($ctx) {
        my @trees = _collect_trees($ctx);
        return _merge_trees(@trees);
    }

    # §6 ForStatement — C-style for loop with enterloop/leaveloop envelope
    method ForStatement($ctx) {
        my @trees = _collect_trees($ctx);
        my $result = Chalk::Bootstrap::ConciseTree->new();
        $result->concat(_merge_trees(@trees));
        $result->push_op(_make_op('enterloop', '{'));
        $result->push_op(_make_op('and', '|'));
        $result->push_op(_make_op('unstack', '0'));
        $result->push_op(_make_op('leaveloop', '2'));
        return $result;
    }

    # §6 ForeachStatement — iterator loop with enteriter/iter/leaveloop envelope
    method ForeachStatement($ctx) {
        my @trees = _collect_trees($ctx);
        my $result = Chalk::Bootstrap::ConciseTree->new();
        $result->concat(_merge_trees(@trees));
        $result->push_op(_make_op('enteriter', '{'));
        $result->push_op(_make_op('iter', '0'));
        $result->push_op(_make_op('and', '|'));
        $result->push_op(_make_op('unstack', '0'));
        $result->push_op(_make_op('leaveloop', '2'));
        return $result;
    }

    # §6 IteratorVariable — transparent pass-through
    method IteratorVariable($ctx) {
        my @trees = _collect_trees($ctx);
        return _merge_trees(@trees);
    }

    # §4 PostfixModifier — postfix control flow (if/unless/while/until/for/foreach)
    method PostfixModifier($ctx) {
        my $scanned = $ctx->scanned_text();
        my @trees = _collect_trees($ctx);
        my $result = _merge_trees(@trees);

        if (defined $scanned && $scanned =~ /\bunless\b/) {
            $result->push_op(_make_op('or', '|'));
        } elsif (defined $scanned && $scanned =~ /\bwhile\b/) {
            $result->push_op(_make_op('and', '|'));
        } elsif (defined $scanned && $scanned =~ /\buntil\b/) {
            $result->push_op(_make_op('or', '|'));
        } elsif (defined $scanned && $scanned =~ /\b(?:for|foreach)\b/) {
            $result->push_op(_make_op('enteriter', '{'));
            $result->push_op(_make_op('iter', '0'));
            $result->push_op(_make_op('and', '|'));
            $result->push_op(_make_op('unstack', '0'));
            $result->push_op(_make_op('leaveloop', '2'));
        } else {
            # Default: postfix if → and
            $result->push_op(_make_op('and', '|'));
        }
        return $result;
    }

    # §5 ElsifChain — transparent pass-through; adds cond_expr for elsif branches
    method ElsifChain($ctx) {
        my @trees = _collect_trees($ctx);
        my $result = _merge_trees(@trees);
        my $scanned = $ctx->scanned_text();
        if (defined $scanned && $scanned =~ /\belsif\b/) {
            $result->push_op(_make_op('cond_expr', '|'));
        }
        return $result;
    }
}
