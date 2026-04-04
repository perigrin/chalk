# ABOUTME: Translates Chalk IR (Constructor/Constant nodes) to SoN::IR::Graph.
# ABOUTME: Bridges Chalk's parser output to perl5-son's graph representation for comparison.
use 5.42.0;
use utf8;
use experimental 'class';

use SoN::IR::NodeFactory;
use SoN::IR::Graph;
use SoN::IR::Stamp;

class Chalk::Bootstrap::IR::ToSoN {

    field $factory;
    field $start;

    # Map of Chalk binary operator strings to SoN node type names
    my %BINOP_MAP = (
        '+'   => 'Add',
        '-'   => 'Subtract',
        '*'   => 'Multiply',
        '/'   => 'Divide',
        '%'   => 'Modulo',
        '**'  => 'Power',
        '.'   => 'Concat',
        '=='  => 'NumEq',
        '!='  => 'NumNe',
        '<'   => 'NumLt',
        '>'   => 'NumGt',
        '<='  => 'NumLe',
        '>='  => 'NumGe',
        '<=>' => 'NumCmp',
        'eq'  => 'StrEq',
        'ne'  => 'StrNe',
        'lt'  => 'StrLt',
        'gt'  => 'StrGt',
        'le'  => 'StrLe',
        'ge'  => 'StrGe',
        'cmp' => 'StrCmp',
        '&&'  => 'And',
        '||'  => 'Or',
        'and' => 'And',
        'or'  => 'Or',
        '&'   => 'BitAnd',
        '|'   => 'BitOr',
        '^'   => 'BitXor',
        '<<'  => 'LeftShift',
        '>>'  => 'RightShift',
        '='   => 'Assign',
    );

    # Map of Chalk unary operator strings to SoN node type names
    my %UNOP_MAP = (
        '!'   => 'Not',
        'not' => 'Not',
        '-'   => 'Negate',
        '~'   => 'Complement',
    );

    # Stamp for common Perl types
    my $str_stamp = SoN::IR::Stamp->new(type => 'Str');
    my $int_stamp = SoN::IR::Stamp->new(type => 'Int');
    my $num_stamp = SoN::IR::Stamp->new(type => 'Num');
    my $bool_stamp = SoN::IR::Stamp->new(type => 'Boolean');
    my $undef_stamp = SoN::IR::Stamp->new(type => 'Undef');

    # Translate a Chalk MethodDecl IR node to a SoN::IR::Graph.
    # $method_node: Constructor:MethodDecl with inputs [name, params, body, ...]
    # $class_name: the enclosing class name (for FieldAccess stash)
    # $field_map: hashref mapping field variable names to indices
    #             e.g., { '$type' => 0, '$value' => 1, '$quantifier' => 2 }
    method translate_method($method_node, $class_name, $field_map) {
        $factory = SoN::IR::NodeFactory->new();
        $start = $factory->make_cfg('Start');

        my $body = $method_node->inputs()->[2];
        my $result = $self->_translate_body($body, $class_name, $field_map);

        # Wrap in Return if the body produced a value
        my $ret;
        if (defined $result) {
            $ret = $factory->make_cfg('Return', inputs => [$start, $result]);
        } else {
            $ret = $factory->make_cfg('Return', inputs => [$start]);
        }

        return SoN::IR::Graph->new(start => $start, returns => [$ret]);
    }

    # Translate a method body (array of Chalk IR nodes) to a SoN value.
    # Returns the last expression's SoN node, or undef for void bodies.
    method _translate_body($body, $class_name, $field_map) {
        my $last;
        for my $item ($body->@*) {
            $last = $self->_translate_node($item, $class_name, $field_map);
        }
        return $last;
    }

    # Translate a single Chalk IR node to a SoN node.
    method _translate_node($node, $class_name, $field_map) {
        return undef unless defined $node;

        if ($node isa Chalk::Bootstrap::IR::Node::Constant) {
            return $self->_translate_constant($node, $class_name, $field_map);
        }

        if ($node isa Chalk::Bootstrap::IR::Node::Constructor) {
            my $class = $node->class();

            if ($class eq 'ReturnStmt') {
                # ReturnStmt(value) — translate value and return it
                # The caller (translate_method) wraps in Return node
                return $self->_translate_node(
                    $node->inputs()->[0], $class_name, $field_map);
            }

            if ($class eq 'BinaryExpr') {
                return $self->_translate_binary($node, $class_name, $field_map);
            }

            if ($class eq 'UnaryExpr') {
                return $self->_translate_unary($node, $class_name, $field_map);
            }

            if ($class eq 'BuiltinCall') {
                return $self->_translate_builtin($node, $class_name, $field_map);
            }

            if ($class eq 'MethodCallExpr') {
                return $self->_translate_method_call($node, $class_name, $field_map);
            }

            if ($class eq 'SubscriptExpr') {
                return $self->_translate_subscript($node, $class_name, $field_map);
            }

            if ($class eq 'TernaryExpr') {
                return $self->_translate_ternary($node, $class_name, $field_map);
            }

            # Fallback: unknown Constructor class
            return undef;
        }

        return undef;
    }

    method _translate_constant($node, $class_name, $field_map) {
        my $val = $node->value();
        my $ct  = $node->const_type() // 'string';

        # Field access: $type, $value, etc. — look up in field_map
        if ($ct eq 'variable' && defined $val && exists $field_map->{$val}) {
            return $factory->make('FieldAccess',
                field_index => $field_map->{$val},
                field_stash => $class_name,
            );
        }

        # Regular variable (param or local) — PadAccess
        if ($ct eq 'variable' && defined $val && $val =~ /^\$(.+)/) {
            return $factory->make('PadAccess',
                targ    => 0,  # targ unknown from source, use 0
                varname => $val,
            );
        }

        # String constant
        if ($ct eq 'string' && defined $val) {
            # Numeric string
            if ($val =~ /^-?[0-9]+$/) {
                return $factory->make('Constant',
                    value => $val, stamp => $int_stamp);
            }
            if ($val =~ /^-?[0-9]+\.[0-9]+$/) {
                return $factory->make('Constant',
                    value => $val, stamp => $num_stamp);
            }
            return $factory->make('Constant',
                value => $val, stamp => $str_stamp);
        }

        # Boolean/special
        if (defined $val) {
            if ($val eq 'true' || $val eq 'false') {
                return $factory->make('Constant',
                    value => $val, stamp => $bool_stamp);
            }
            if ($val eq 'undef') {
                return $factory->make('Constant',
                    value => undef, stamp => $undef_stamp);
            }
        }

        return $factory->make('Constant',
            value => $val, stamp => $str_stamp);
    }

    method _translate_binary($node, $class_name, $field_map) {
        my $op_str = $node->inputs()->[0]->value();
        my $left   = $self->_translate_node(
            $node->inputs()->[1], $class_name, $field_map);
        my $right  = $self->_translate_node(
            $node->inputs()->[2], $class_name, $field_map);

        my $son_op = $BINOP_MAP{$op_str};
        if (defined $son_op && defined $left && defined $right) {
            return $factory->make($son_op, inputs => [$left, $right]);
        }

        # Concatenation assignment, etc. — fall through
        return undef;
    }

    method _translate_unary($node, $class_name, $field_map) {
        my $op_str  = $node->inputs()->[0]->value();
        my $operand = $self->_translate_node(
            $node->inputs()->[1], $class_name, $field_map);

        my $son_op = $UNOP_MAP{$op_str};
        if (defined $son_op && defined $operand) {
            return $factory->make($son_op, inputs => [$operand]);
        }
        return undef;
    }

    method _translate_builtin($node, $class_name, $field_map) {
        my $name = $node->inputs()->[0]->value();
        my @args = map {
            $self->_translate_node($_, $class_name, $field_map)
        } $node->inputs()->[1]->@*;

        if ($name eq 'defined' && @args == 1 && defined $args[0]) {
            return $factory->make('Defined', inputs => [$args[0]]);
        }

        if ($name eq 'length' && @args == 1 && defined $args[0]) {
            return $factory->make('Length', inputs => [$args[0]]);
        }

        # Generic builtin → Call node
        my $name_node = $factory->make('Constant',
            value => $name, stamp => $str_stamp);
        my @valid_args = grep { defined } @args;
        return $factory->make('Call',
            dispatch_kind => 'builtin',
            name          => $name,
            inputs        => [$name_node, @valid_args],
        );
    }

    method _translate_method_call($node, $class_name, $field_map) {
        my $invocant = $self->_translate_node(
            $node->inputs()->[0], $class_name, $field_map);
        my $method_name = $node->inputs()->[1]->value();
        my $args_node = $node->inputs()->[2];
        my @args;
        if (ref($args_node) eq 'ARRAY') {
            @args = map {
                $self->_translate_node($_, $class_name, $field_map)
            } $args_node->@*;
        }

        my @valid = grep { defined } ($invocant, @args);
        return $factory->make('Call',
            dispatch_kind => 'method',
            name          => $method_name,
            inputs        => \@valid,
        );
    }

    method _translate_subscript($node, $class_name, $field_map) {
        my $target = $self->_translate_node(
            $node->inputs()->[0], $class_name, $field_map);
        my $index = $self->_translate_node(
            $node->inputs()->[1], $class_name, $field_map);

        if (defined $target && defined $index) {
            return $factory->make('Subscript',
                inputs => [$target, $index]);
        }
        return undef;
    }

    method _translate_ternary($node, $class_name, $field_map) {
        my $cond = $self->_translate_node(
            $node->inputs()->[0], $class_name, $field_map);
        my $true_val = $self->_translate_node(
            $node->inputs()->[1], $class_name, $field_map);
        my $false_val = $self->_translate_node(
            $node->inputs()->[2], $class_name, $field_map);

        return undef unless defined $cond;

        # Lower to If + Proj + Region + Phi (same as SoN::FromOptree)
        my $if_node = $factory->make_cfg('If', inputs => [$start, $cond]);
        my $true_proj = $factory->make_cfg('Proj',
            inputs => [$if_node], index => 0);
        my $false_proj = $factory->make_cfg('Proj',
            inputs => [$if_node], index => 1);
        my $region = $factory->make_cfg('Region',
            inputs => [$true_proj, $false_proj]);

        if (defined $true_val && defined $false_val) {
            return $factory->make('Phi',
                inputs => [$region, $true_val, $false_val]);
        }
        return undef;
    }
}

1;
