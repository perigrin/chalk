# ABOUTME: Semantic actions for Perl grammar that build Perl IR nodes from parse results.
# ABOUTME: One method per grammar rule, constructing Constructor:Program/UseDecl/ClassDecl/etc.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::IR::NodeFactory;

class Chalk::Bootstrap::Perl::Actions {
    field $factory;

    ADJUST {
        $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    }

    # Helper: collect all leaves with defined IR focuses (Constructor or Constant nodes)
    my sub _collect_ir_leaves($ctx) {
        my @results;
        for my $leaf ($ctx->leaves()) {
            my $focus = $leaf->extract();
            if (defined $focus) {
                push @results, $leaf;
            }
        }
        return @results;
    }

    # Helper: collect focus values from IR leaves
    my sub _collect_ir_values($ctx) {
        return map { $_->extract() } _collect_ir_leaves($ctx);
    }

    # Helper: find first IR leaf whose focus is a Constructor with given class
    my sub _find_constructor($ctx, $class) {
        for my $leaf (_collect_ir_leaves($ctx)) {
            my $focus = $leaf->extract();
            if ($focus isa Chalk::Bootstrap::IR::Node::Constructor
                    && $focus->class() eq $class) {
                return $focus;
            }
        }
        return undef;
    }

    # Helper: collect all IR values that are Constructors with given class
    my sub _collect_constructors($ctx, $class) {
        my @results;
        for my $leaf (_collect_ir_leaves($ctx)) {
            my $focus = $leaf->extract();
            if ($focus isa Chalk::Bootstrap::IR::Node::Constructor
                    && $focus->class() eq $class) {
                push @results, $focus;
            }
        }
        return @results;
    }

    # Helper: find first Constant node in leaves
    my sub _find_constant($ctx) {
        for my $leaf (_collect_ir_leaves($ctx)) {
            my $focus = $leaf->extract();
            if ($focus isa Chalk::Bootstrap::IR::Node::Constant) {
                return $focus;
            }
        }
        return undef;
    }

    # Helper: collect all Constant nodes from leaves
    my sub _collect_constants($ctx) {
        my @results;
        for my $leaf (_collect_ir_leaves($ctx)) {
            my $focus = $leaf->extract();
            if ($focus isa Chalk::Bootstrap::IR::Node::Constant) {
                push @results, $focus;
            }
        }
        return @results;
    }

    # Helper: make a Constant IR node
    my sub _make_const($factory, $value) {
        return $factory->make('Constant', const_type => 'string', value => $value);
    }

    # Post-process statement list to fix grammar ambiguity artifacts.
    # The ambiguous grammar sometimes parses compound statements as
    # separate items. These fixups merge them back together:
    # - `return 'Start'` → ReturnStmt(Constant('Start'))
    # - `die "message"` → DieCall([Constant('message')])
    # - `use Foo 'bar'` (split) → UseDecl(Foo, ['bar'])
    my sub _fixup_stmts($factory, $stmts) {
        my @result;
        my $i = 0;
        while ($i <= $#$stmts) {
            my $item = $stmts->[$i];
            if ($item isa Chalk::Bootstrap::IR::Node::Constant
                    && defined $item->value()
                    && $item->value() eq 'return'
                    && $i + 1 <= $#$stmts) {
                # Merge return + value into ReturnStmt
                $i++;
                my $value = $stmts->[$i];
                push @result, $factory->make('Constructor',
                    class => 'ReturnStmt',
                    value => $value,
                );
            } elsif ($item isa Chalk::Bootstrap::IR::Node::Constant
                    && defined $item->value()
                    && $item->value() eq 'die'
                    && $i + 1 <= $#$stmts) {
                # Merge die + single argument into DieCall.
                # Consumes only one following node to avoid absorbing
                # unrelated statements in multi-statement bodies.
                $i++;
                push @result, $factory->make('Constructor',
                    class => 'DieCall',
                    args  => [$stmts->[$i]],
                );
            } elsif ($item isa Chalk::Bootstrap::IR::Node::Constructor
                    && $item->class() eq 'UseDecl'
                    && !defined $item->inputs()->[1]
                    && $i + 1 <= $#$stmts
                    && $stmts->[$i + 1] isa Chalk::Bootstrap::IR::Node::Constant) {
                # Merge UseDecl(module, undef) + bare Constant into
                # UseDecl(module, [Constant]). Grammar ambiguity sometimes
                # splits `use Foo 'bar'` into separate statements.
                my @import_args;
                while ($i + 1 <= $#$stmts
                        && $stmts->[$i + 1] isa Chalk::Bootstrap::IR::Node::Constant
                        && !($stmts->[$i + 1]->value() =~ /^[a-zA-Z_]/
                             && $i + 2 <= $#$stmts)) {
                    $i++;
                    push @import_args, $stmts->[$i];
                }
                if (@import_args) {
                    push @result, $factory->make('Constructor',
                        class       => 'UseDecl',
                        module_name => $item->inputs()->[0],
                        import_args => \@import_args,
                    );
                } else {
                    push @result, $item;
                }
            } else {
                push @result, $item;
            }
            $i++;
        }
        return \@result;
    }

    # §2 Program ::= _ StatementList? _
    # Collects all statement-level IR nodes into Constructor:Program
    method Program($ctx) {
        my @stmts;
        for my $val (_collect_ir_values($ctx)) {
            if (ref($val) eq 'ARRAY') {
                # StatementList returns arrayref
                push @stmts, $val->@*;
            } elsif ($val isa Chalk::Bootstrap::IR::Node) {
                push @stmts, $val;
            }
        }
        return $factory->make('Constructor',
            class      => 'Program',
            statements => \@stmts,
        );
    }

    # §2 StatementList ::= StatementItem | StatementList _ StatementItem
    # Collects all statement IR nodes into an arrayref
    method StatementList($ctx) {
        my @stmts;
        for my $val (_collect_ir_values($ctx)) {
            if (ref($val) eq 'ARRAY') {
                # Nested StatementList result — flatten
                push @stmts, $val->@*;
            } elsif ($val isa Chalk::Bootstrap::IR::Node) {
                push @stmts, $val;
            }
        }
        return _fixup_stmts($factory, \@stmts);
    }

    # §2 StatementItem — pass through the child IR value
    method StatementItem($ctx) {
        my @values = _collect_ir_values($ctx);
        # Return the first non-trivial IR value
        for my $val (@values) {
            return $val if $val isa Chalk::Bootstrap::IR::Node;
        }
        return undef;
    }

    # §3 SimpleStatement — transparent pass-through
    method SimpleStatement($ctx) {
        my @values = _collect_ir_values($ctx);
        for my $val (@values) {
            return $val if $val isa Chalk::Bootstrap::IR::Node;
        }
        return undef;
    }

    # §3 CompoundStatement — transparent pass-through
    method CompoundStatement($ctx) {
        my @values = _collect_ir_values($ctx);
        for my $val (@values) {
            return $val if $val isa Chalk::Bootstrap::IR::Node;
        }
        return undef;
    }

    # §4 ExpressionStatement — transparent pass-through
    method ExpressionStatement($ctx) {
        my @values = _collect_ir_values($ctx);
        for my $val (@values) {
            return $val if $val isa Chalk::Bootstrap::IR::Node;
        }
        return undef;
    }

    # §7 UseDeclaration ::= /use\b/ WS ModuleName
    #                      | /use\b/ WS ModuleName WS ImportList
    method UseDeclaration($ctx) {
        my @leaves = _collect_ir_leaves($ctx);
        my $module_name;
        my $import_args;

        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule();

            if (defined $rule && $rule eq 'ModuleName'
                    && $focus isa Chalk::Bootstrap::IR::Node::Constant) {
                $module_name = $focus;
            } elsif (defined $rule && $rule eq 'ImportList'
                    && ref($focus) eq 'ARRAY') {
                $import_args = $focus;
            }
        }

        # If no module name found from ModuleName rule, look for any Constant
        if (!defined $module_name) {
            $module_name = _find_constant($ctx);
        }

        return $factory->make('Constructor',
            class       => 'UseDecl',
            module_name => $module_name,
            import_args => $import_args,
        );
    }

    # §7 ModuleName ::= QualifiedIdentifier | Version | QualifiedIdentifier WS Version
    # Returns a Constant with the module name
    method ModuleName($ctx) {
        # Collect all text from scanned terminals
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return _make_const($factory, $text);
    }

    # §7 ImportList ::= ExpressionList
    # Returns arrayref of Constant nodes for import arguments
    method ImportList($ctx) {
        my @values = _collect_ir_values($ctx);
        my @imports;
        for my $val (@values) {
            if (ref($val) eq 'ARRAY') {
                push @imports, $val->@*;
            } elsif ($val isa Chalk::Bootstrap::IR::Node) {
                push @imports, $val;
            }
        }
        return \@imports;
    }

    # §9 ClassBlock ::= /class\b/ WS QualifiedIdentifier AttributeList? _ Block
    method ClassBlock($ctx) {
        my @leaves = _collect_ir_leaves($ctx);
        my $class_name;
        my $parent;
        my @body;

        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule();

            if ($focus isa Chalk::Bootstrap::IR::Node::Constant) {
                if (!defined $class_name) {
                    # First Constant is the class name (from QualifiedIdentifier)
                    $class_name = $focus;
                }
            } elsif (ref($focus) eq 'ARRAY') {
                # Body statements from Block or parent info from AttributeList
                if (defined $rule && $rule eq 'AttributeList') {
                    # AttributeList returns arrayref of attribute data
                    # Look for :isa(Parent) → parent name Constant
                    for my $attr ($focus->@*) {
                        if ($attr isa Chalk::Bootstrap::IR::Node::Constructor
                                && $attr->class() eq '_Attribute') {
                            my $attr_name = $attr->inputs()->[0];
                            if (defined $attr_name
                                    && $attr_name->value() eq 'isa') {
                                $parent = $attr->inputs()->[1];
                            }
                        }
                    }
                } elsif (defined $rule && $rule eq 'Block') {
                    # Block returns arrayref of body statements
                    @body = $focus->@*;
                } else {
                    # Fallback: use as body
                    @body = $focus->@*;
                }
            }
        }

        return $factory->make('Constructor',
            class  => 'ClassDecl',
            name   => $class_name,
            parent => $parent,
            body   => \@body,
        );
    }

    # §9 MethodDefinition ::= /method\b/ WS Identifier AttributeList? _ Signature? _ Block
    method MethodDefinition($ctx) {
        my @leaves = _collect_ir_leaves($ctx);
        my $method_name;
        my @params;
        my @body;

        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule();

            if ($focus isa Chalk::Bootstrap::IR::Node::Constant
                    && !defined $method_name) {
                $method_name = $focus;
            } elsif (ref($focus) eq 'ARRAY') {
                if (defined $rule && ($rule eq 'Signature'
                        || $rule eq 'SignatureParams')) {
                    @params = $focus->@*;
                } elsif (defined $rule && $rule eq 'Block') {
                    @body = $focus->@*;
                } else {
                    # Ambiguous: if we haven't seen params yet and items look
                    # like param names, treat as params. Otherwise body.
                    if (!@body) {
                        @body = $focus->@*;
                    }
                }
            }
        }

        return $factory->make('Constructor',
            class  => 'MethodDecl',
            name   => $method_name,
            params => \@params,
            body   => \@body,
        );
    }

    # §9 SubroutineDefinition — pass through (for Tier A we skip sub definitions)
    method SubroutineDefinition($ctx) {
        return undef;
    }

    # §9 AdjustBlock — not in Tier A
    method AdjustBlock($ctx) {
        return undef;
    }

    # §10 AttributeList ::= WS Attribute | AttributeList WS Attribute
    # Returns arrayref of _Attribute Constructor nodes
    method AttributeList($ctx) {
        my @attrs;
        for my $val (_collect_ir_values($ctx)) {
            if (ref($val) eq 'ARRAY') {
                push @attrs, $val->@*;
            } elsif ($val isa Chalk::Bootstrap::IR::Node::Constructor
                    && $val->class() eq '_Attribute') {
                push @attrs, $val;
            }
        }
        return \@attrs;
    }

    # §10 Attribute ::= /:/ _ Identifier | /:/ _ Identifier _ /\(/ _ QualifiedIdentifier _ /\)/
    # Returns _Attribute Constructor with name and optional value
    method Attribute($ctx) {
        my @constants = _collect_constants($ctx);
        my $attr_name = $constants[0];  # Identifier
        my $attr_value = $constants[1]; # QualifiedIdentifier (optional)

        return $factory->make('Constructor',
            class  => '_Attribute',
            name   => $attr_name,
            parent => $attr_value, # reuse parent slot for attribute value
            body   => undef,       # unused
        );
    }

    # §11 Signature ::= /\(/ _ /\)/ | /\(/ _ SignatureParams _ /\)/
    # Returns arrayref of param name Constants
    method Signature($ctx) {
        my @values = _collect_ir_values($ctx);
        for my $val (@values) {
            return $val if ref($val) eq 'ARRAY';
        }
        return [];
    }

    # §11 SignatureParams ::= SignatureParam | SignatureParams _ /,/ _ SignatureParam
    method SignatureParams($ctx) {
        my @params;
        for my $val (_collect_ir_values($ctx)) {
            if (ref($val) eq 'ARRAY') {
                push @params, $val->@*;
            } elsif ($val isa Chalk::Bootstrap::IR::Node::Constant) {
                push @params, $val;
            }
        }
        return \@params;
    }

    # §11 SignatureParam — transparent
    method SignatureParam($ctx) {
        my @values = _collect_ir_values($ctx);
        for my $val (@values) {
            return $val if $val isa Chalk::Bootstrap::IR::Node::Constant;
        }
        return undef;
    }

    # §11 ScalarSignatureParam ::= ScalarVariable | ScalarVariable _ /=/ _ Expression
    method ScalarSignatureParam($ctx) {
        # Get the variable name from scanned text
        my $text = $ctx->scanned_text();
        # Extract just the variable name (first $word)
        if ($text =~ /(\$\w+)/) {
            return _make_const($factory, $1);
        }
        return undef;
    }

    # §11 SlurpySignatureParam — return variable name
    method SlurpySignatureParam($ctx) {
        my $text = $ctx->scanned_text();
        if ($text =~ /([@%]\w+)/) {
            return _make_const($factory, $1);
        }
        return undef;
    }

    # §12 Expression — transparent pass-through
    method Expression($ctx) {
        my @values = _collect_ir_values($ctx);
        for my $val (@values) {
            return $val if $val isa Chalk::Bootstrap::IR::Node;
        }
        return undef;
    }

    # §12 ExpressionList — collect into arrayref
    method ExpressionList($ctx) {
        my @items;
        for my $val (_collect_ir_values($ctx)) {
            if (ref($val) eq 'ARRAY') {
                push @items, $val->@*;
            } elsif ($val isa Chalk::Bootstrap::IR::Node) {
                push @items, $val;
            }
        }
        return \@items;
    }

    # §13 Atom — transparent pass-through
    method Atom($ctx) {
        my @values = _collect_ir_values($ctx);
        for my $val (@values) {
            return $val if $val isa Chalk::Bootstrap::IR::Node;
        }
        return undef;
    }

    # §16 CallExpression — detect return/die builtins, produce IR nodes
    # CallExpression ::= Identifier _ /\(/ _ ExpressionList? _ /\)/
    #                   | Identifier WS ExpressionList
    #                   | Identifier WS Block WS ExpressionList
    #                   | Identifier WS Block
    method CallExpression($ctx) {
        # Extract function name from scanned text
        my $func_name;
        my @leaves = _collect_ir_leaves($ctx);

        # Find the identifier (first Constant leaf that looks like a name)
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule();
            if ($focus isa Chalk::Bootstrap::IR::Node::Constant
                    && defined $rule
                    && ($rule eq 'Identifier' || $rule eq 'QualifiedIdentifier')) {
                $func_name = $focus->value();
                last;
            }
        }

        # If no named leaf, try scanning text for identifier
        if (!defined $func_name) {
            my $text = $ctx->scanned_text();
            if ($text =~ /^[\s]*([a-zA-Z_]\w*)/) {
                $func_name = $1;
            }
        }

        # Collect argument values
        my @args;
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule();
            # Skip the function name itself
            next if $focus isa Chalk::Bootstrap::IR::Node::Constant
                && defined $rule
                && ($rule eq 'Identifier' || $rule eq 'QualifiedIdentifier')
                && defined $focus->value()
                && $focus->value() eq $func_name;

            if (ref($focus) eq 'ARRAY') {
                push @args, $focus->@*;
            } elsif ($focus isa Chalk::Bootstrap::IR::Node) {
                push @args, $focus;
            }
        }

        if (defined $func_name && $func_name eq 'return') {
            # return EXPR → ReturnStmt
            my $value = $args[0]; # single value for Tier A
            return $factory->make('Constructor',
                class => 'ReturnStmt',
                value => $value,
            );
        }

        if (defined $func_name && $func_name eq 'die') {
            # die EXPR → DieCall
            return $factory->make('Constructor',
                class => 'DieCall',
                args  => \@args,
            );
        }

        # Generic function call — not needed for Tier A but return undef
        return undef;
    }

    # §13 MapGrepExpression — not in Tier A
    method MapGrepExpression($ctx) {
        return undef;
    }

    # §19 Literal — transparent pass-through
    method Literal($ctx) {
        my @values = _collect_ir_values($ctx);
        for my $val (@values) {
            return $val if $val isa Chalk::Bootstrap::IR::Node;
        }
        # Handle undef/true/false literals by scanned text
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        if ($text eq 'undef' || $text eq 'true' || $text eq 'false') {
            return _make_const($factory, $text);
        }
        return undef;
    }

    # §19 StringLiteral — extract string content
    method StringLiteral($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        # Strip quotes from single/double-quoted strings
        if ($text =~ /^'((?:[^'\\]|\\.)*)'$/) {
            my $content = $1;
            $content =~ s/\\'/'/g;
            $content =~ s/\\\\/\\/g;
            return _make_const($factory, $content);
        }
        if ($text =~ /^"((?:[^"\\]|\\.)*)"$/) {
            my $content = $1;
            $content =~ s/\\"/"/g;
            $content =~ s/\\\\/\\/g;
            return _make_const($factory, $content);
        }
        return _make_const($factory, $text);
    }

    # §19 NumericLiteral — return as Constant
    method NumericLiteral($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return _make_const($factory, $text);
    }

    # §19 RegexLiteral — return as Constant
    method RegexLiteral($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return _make_const($factory, $text);
    }

    # §20 Identifier — return as Constant
    method Identifier($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return _make_const($factory, $text);
    }

    # §20 QualifiedIdentifier — return as Constant
    method QualifiedIdentifier($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return _make_const($factory, $text);
    }

    # §20 Version — return as Constant
    method Version($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return _make_const($factory, $text);
    }

    # §20 Block ::= /\{/ _ StatementList? _ /\}/
    # Returns arrayref of body statement IR nodes
    method Block($ctx) {
        my @stmts;
        for my $val (_collect_ir_values($ctx)) {
            if (ref($val) eq 'ARRAY') {
                push @stmts, $val->@*;
            } elsif ($val isa Chalk::Bootstrap::IR::Node) {
                push @stmts, $val;
            }
        }
        return _fixup_stmts($factory, \@stmts);
    }

    # §18 Variable — return variable name as Constant
    method Variable($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return _make_const($factory, $text);
    }

    # §18 ScalarVariable — return as Constant
    method ScalarVariable($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return _make_const($factory, $text);
    }

    # §18 ArrayVariable — return as Constant
    method ArrayVariable($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return _make_const($factory, $text);
    }

    # §18 HashVariable — return as Constant
    method HashVariable($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return _make_const($factory, $text);
    }

    # §13 QwLiteral — return array of Constants
    method QwLiteral($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        if ($text =~ /^qw\s*\(([^)]*)\)$/) {
            my @words = split /\s+/, $1;
            @words = grep { $_ ne '' } @words;
            return [map { _make_const($factory, $_) } @words];
        }
        return [];
    }

    # §8 VariableDeclaration — not in Tier A (handled as Expression)
    method VariableDeclaration($ctx) {
        return undef;
    }

    # §8 FieldDeclaration — not in Tier A
    method FieldDeclaration($ctx) {
        return undef;
    }

    # §13 ParenExpr — transparent
    method ParenExpr($ctx) {
        my @values = _collect_ir_values($ctx);
        for my $val (@values) {
            return $val if $val isa Chalk::Bootstrap::IR::Node;
            return $val if ref($val) eq 'ARRAY';
        }
        return undef;
    }

    # §13 ArrayConstructor — not in Tier A
    method ArrayConstructor($ctx) {
        return undef;
    }

    # §13 HashConstructor — not in Tier A
    method HashConstructor($ctx) {
        return undef;
    }

    # §13 AnonymousSub — not in Tier A
    method AnonymousSub($ctx) {
        return undef;
    }

    # §14 UnaryExpression — not in Tier A
    method UnaryExpression($ctx) {
        return undef;
    }

    # §15 BinaryExpression — not in Tier A
    method BinaryExpression($ctx) {
        return undef;
    }

    # §15 BinaryOp — not in Tier A
    method BinaryOp($ctx) {
        return undef;
    }

    # §16 PostfixExpression — transparent
    method PostfixExpression($ctx) {
        my @values = _collect_ir_values($ctx);
        for my $val (@values) {
            return $val if $val isa Chalk::Bootstrap::IR::Node;
        }
        return undef;
    }

    # §16 MethodCall — not in Tier A
    method MethodCall($ctx) {
        return undef;
    }

    # §16 Subscript — not in Tier A
    method Subscript($ctx) {
        return undef;
    }

    # §16 PostfixDeref — not in Tier A
    method PostfixDeref($ctx) {
        return undef;
    }

    # §16 PostfixIncDec — not in Tier A
    method PostfixIncDec($ctx) {
        return undef;
    }

    # §17 TernaryExpression — not in Tier A
    method TernaryExpression($ctx) {
        return undef;
    }

    # §17 AssignmentExpression — not in Tier A
    method AssignmentExpression($ctx) {
        return undef;
    }

    # §17 AssignOp — not in Tier A
    method AssignOp($ctx) {
        return undef;
    }

    # §4 PostfixModifier — not in Tier A
    method PostfixModifier($ctx) {
        return undef;
    }

    # §5 IfStatement — not in Tier A
    method IfStatement($ctx) {
        return undef;
    }

    # §5 ElsifChain — not in Tier A
    method ElsifChain($ctx) {
        return undef;
    }

    # §6 WhileStatement — not in Tier A
    method WhileStatement($ctx) {
        return undef;
    }

    # §6 ForStatement — not in Tier A
    method ForStatement($ctx) {
        return undef;
    }

    # §6 ForeachStatement — not in Tier A
    method ForeachStatement($ctx) {
        return undef;
    }

    # §6 IteratorVariable — not in Tier A
    method IteratorVariable($ctx) {
        return undef;
    }

    # §8 VariableList — not in Tier A
    method VariableList($ctx) {
        return undef;
    }

    # §8 DefaultValue — not in Tier A
    method DefaultValue($ctx) {
        return undef;
    }
}

1;
