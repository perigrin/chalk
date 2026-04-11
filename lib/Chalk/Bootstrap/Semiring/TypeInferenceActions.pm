# ABOUTME: Type inference action methods dispatched by TypeInference on_complete.
# ABOUTME: Each method receives a Context via extend(), returns a focus hash for the completed rule.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Grammar::Perl::TypeLibrary;
class Chalk::Bootstrap::Semiring::TypeInferenceActions {

    # Helper: Get rightmost type from Context tree (for wrapper rules)
    my sub _get_rightmost_type($ctx) {
        return unless defined $ctx;
        my $focus = $ctx->extract();
        if (defined $focus && exists $focus->{type}) {
            return $focus->{type};
        }
        # Walk children right-to-left
        my @children = $ctx->children()->@*;
        for my $child (reverse @children) {
            my $t = __SUB__->($child);
            return $t if defined $t;
        }
        return;
    }

    # Helper: Get leftmost type from Context tree (for assignment LHS)
    my sub _get_leftmost_type($ctx) {
        return unless defined $ctx;
        my $focus = $ctx->extract();
        if (defined $focus && exists $focus->{type}) {
            return $focus->{type};
        }
        # Walk children left-to-right
        for my $child ($ctx->children()->@*) {
            my $t = __SUB__->($child);
            return $t if defined $t;
        }
        return;
    }

    # Helper: Get ident_text from Context tree (for method/function names)
    my sub _get_ident_text($ctx) {
        return unless defined $ctx;
        my $focus = $ctx->extract();
        if (defined $focus && exists $focus->{ident_text}) {
            return $focus->{ident_text};
        }
        for my $child ($ctx->children()->@*) {
            my $found = __SUB__->($child);
            return $found if defined $found;
        }
        return;
    }

    # Method return type registry: method_name => return_type
    # Populated by MethodDefinition on_complete, consumed by MethodCall lookups.
    # Scoped per file parse (reset via reset_method_registry).
    my %_method_returns;

    # Helper: Get op_text from Context tree (for operator rules)
    # Follows leaf-finding semantics: stops at focused nodes.
    my sub _get_op_text($ctx) {
        return unless defined $ctx;
        my $focus = $ctx->extract();
        if (defined $focus) {
            return $focus->{op_text};
        }
        for my $child ($ctx->children()->@*) {
            my $found = __SUB__->($child);
            return $found if defined $found;
        }
        return;
    }

    # Wrapper rules: passthrough child's type

    # Helper: Get call_symbol from Context tree (for builtin disambiguation)
    my sub _get_call_symbol($ctx) {
        return unless defined $ctx;
        my $focus = $ctx->extract();
        if (defined $focus && ref($focus) eq 'HASH' && exists $focus->{call_symbol}) {
            return $focus->{call_symbol};
        }
        for my $child ($ctx->children()->@*) {
            my $t = __SUB__->($child);
            return $t if defined $t;
        }
        return;
    }

    method Atom($ctx) {
        my $child_type = _get_rightmost_type($ctx);
        my $call_sym = _get_call_symbol($ctx);
        return { valid => true,
            ($child_type ? (type => $child_type) : ()),
            ($call_sym   ? (call_symbol => $call_sym) : ()),
        };
    }

    method Expression($ctx) {
        my $child_type = _get_rightmost_type($ctx);
        my $call_sym = _get_call_symbol($ctx);
        return { valid => true,
            ($child_type ? (type => $child_type) : ()),
            ($call_sym   ? (call_symbol => $call_sym) : ()),
        };
    }

    method PostfixExpression($ctx) {
        my $child_type = _get_rightmost_type($ctx);
        return { valid => true, ($child_type ? (type => $child_type) : ()) };
    }

    # Rich rules: compute type from operator/signature

    method BinaryExpression($ctx) {
        my $op = _get_op_text($ctx);
        my $result_type;
        if (defined $op) {
            my $sig = Chalk::Grammar::Perl::TypeLibrary::get_binary_op($op);
            if ($sig && $sig->{result} ne 'Any') {
                $result_type = $sig->{result};
            }
            # result 'Any' → leave type undef (unknown)
        } else {
            # No op_text: preserve child type (intermediate completion)
            $result_type = _get_rightmost_type($ctx);
        }
        return { valid => true, ($result_type ? (type => $result_type) : ()) };
    }

    method UnaryExpression($ctx) {
        my $op = _get_op_text($ctx);
        my $result_type;
        if (defined $op) {
            my $sig = Chalk::Grammar::Perl::TypeLibrary::get_unary_op($op);
            $result_type = $sig->{result} if $sig;
        }
        return { valid => true, ($result_type ? (type => $result_type) : ()) };
    }

    # Helper: Get list_arity from Context tree
    my sub _get_list_arity($ctx) {
        return unless defined $ctx;
        my $focus = $ctx->extract();
        if (defined $focus) {
            return $focus->{list_arity};
        }
        for my $child ($ctx->children()->@*) {
            my $found = __SUB__->($child);
            return $found if defined $found;
        }
        return;
    }

    # Helper: Get item_types from Context tree
    my sub _get_item_types($ctx) {
        return unless defined $ctx;
        my $focus = $ctx->extract();
        if (defined $focus) {
            return $focus->{item_types};
        }
        for my $child ($ctx->children()->@*) {
            my $found = __SUB__->($child);
            return $found if defined $found;
        }
        return;
    }

    # Helper: Search for item_types in previous ExpressionList children
    my sub _get_prev_item_types($ctx) {
        return unless defined $ctx;
        my $focus = $ctx->extract();
        if (defined $focus && exists $focus->{item_types}) {
            return $focus->{item_types};
        }
        for my $child ($ctx->children()->@*) {
            my $found = __SUB__->($child);
            return $found if defined $found;
        }
        return;
    }

    # ExpressionList: arity/item_types tracking
    # alt 0 = single Expression (arity 1)
    # alt 1 = ExpressionList , Expression (arity = child + 1)
    # alt 2 = ExpressionList => Expression (arity = child + 1)
    # alt 3 = trailing comma (arity preserved)

    method ExpressionList($ctx, $alt_idx = 0) {
        my ($arity, $item_types);
        if ($alt_idx == 0) {
            $arity = 1;
            my $type = _get_rightmost_type($ctx);
            # type can be undef for non-typed expressions (e.g. function calls)
            $item_types = [$type];
        } elsif ($alt_idx == 1 || $alt_idx == 2) {
            $arity = (_get_list_arity($ctx) // 1) + 1;
            my $prev = _get_prev_item_types($ctx) // [];
            my $new_type = _get_rightmost_type($ctx);
            $item_types = [$prev->@*, $new_type];
        } else {
            $arity = _get_list_arity($ctx);
            $item_types = _get_item_types($ctx) // _get_prev_item_types($ctx);
        }
        return {
            valid => true,
            ($arity ? (list_arity => $arity) : ()),
            ($item_types ? (item_types => $item_types) : ()),
        };
    }

    # CallExpression is handled inline in TypeInference.pm (not dispatched here)
    # because it requires complex multi-walker logic with builtin_lookup and
    # type_satisfies for per-position argument validation.

    # Boundary rules: preserve type, clear call_symbol/op_text

    method ParenExpr($ctx) {
        my $child_type = _get_rightmost_type($ctx);
        return {
            valid => true,
            ($child_type ? (type => $child_type) : ()),
        };
    }

    method Block($ctx) {
        my $child_type = _get_rightmost_type($ctx);
        return {
            valid => true,
            ($child_type ? (type => $child_type) : ()),
        };
    }

    method Signature($ctx) {
        my $child_type = _get_rightmost_type($ctx);
        return {
            valid => true,
            ($child_type ? (type => $child_type) : ()),
        };
    }

    method Attribute($ctx) {
        my $child_type = _get_rightmost_type($ctx);
        return {
            valid => true,
            ($child_type ? (type => $child_type) : ()),
        };
    }

    # Subscript: type depends on alt_idx

    method Subscript($ctx, $alt_idx = 0) {
        my $sub_type;
        if ($alt_idx <= 1) {
            # alt 0 = [...] (array), alt 1 = {...} (hash) → element is Scalar
            $sub_type = 'Scalar';
        }
        # alt 2+ = ->() deref-call: type unknown (undef)
        return {
            valid => true,
            ($sub_type ? (type => $sub_type) : ()),
        };
    }

    # PostfixDeref: type depends on alt_idx

    method PostfixDeref($ctx, $alt_idx = 0) {
        my $type_tag;
        if ($alt_idx == 0) {
            $type_tag = 'Array';
        } elsif ($alt_idx == 1) {
            $type_tag = 'Hash';
        } else {
            $type_tag = 'Scalar';
        }
        return { valid => true, type => $type_tag };
    }

    # Fixed return types

    method PostfixIncDec($ctx) {
        return { valid => true, type => 'Num' };
    }

    method AnonymousSub($ctx) {
        return { valid => true, type => 'Code' };
    }

    method QwLiteral($ctx) {
        return { valid => true, type => 'List' };
    }

    method ArrayConstructor($ctx) {
        return { valid => true, type => 'ArrayRef' };
    }

    method HashConstructor($ctx) {
        return { valid => true, type => 'HashRef' };
    }

    # Unknown types (no static type information)

    method TernaryExpression($ctx) {
        return { valid => true };
    }

    method AssignmentExpression($ctx) {
        # Derive eval_context from LHS variable sigil type
        my $lhs_type = _get_leftmost_type($ctx);
        my $eval_context;
        if (defined $lhs_type) {
            if ($lhs_type eq 'Scalar') {
                $eval_context = 'Scalar';
            } elsif ($lhs_type eq 'Array' || $lhs_type eq 'Hash') {
                $eval_context = 'List';
            }
        }
        return {
            valid => true,
            ($eval_context ? (eval_context => $eval_context) : ()),
        };
    }

    method ExpressionStatement($ctx) {
        return { valid => true, eval_context => 'Void' };
    }

    method MethodCall($ctx) {
        return { valid => true };
    }

    # MethodDefinition: extract method name and body return type for registry
    method MethodDefinition($ctx) {
        my $method_name = _get_ident_text($ctx);
        my $body_type = _get_rightmost_type($ctx);

        # Register method return type if both name and type are available
        if (defined $method_name && defined $body_type) {
            $_method_returns{$method_name} = $body_type;
        }

        return {
            valid => true,
            ($method_name ? (method_name => $method_name) : ()),
            ($body_type ? (method_return_type => $body_type) : ()),
        };
    }

    # Dispatch an action method by name, returning the focus hash.
    # Avoids closure capture and dynamic coderef calls that the XS
    # codegen cannot handle. The caller passes the rule name as a
    # string; this method resolves it via can() and calls it.
    method dispatch($rule_name, $ctx, $alt_idx) {
        my $method = $self->can($rule_name);
        return unless $method;
        if (defined $alt_idx) {
            return $self->$method($ctx, $alt_idx);
        }
        return $self->$method($ctx);
    }

    # Registry access methods for method return types
    sub register_method_return($name, $type) {
        $_method_returns{$name} = $type;
    }

    sub lookup_method_return($name) {
        return $_method_returns{$name};
    }

    sub reset_method_registry() {
        %_method_returns = ();
    }
}
