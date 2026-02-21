# ABOUTME: Type inference action methods dispatched by TypeInference on_complete.
# ABOUTME: Each method receives a Context and tags hash, returns focus tags or undef to reject.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Grammar::Perl::TypeLibrary;
use Chalk::Grammar::Perl::KeywordTable;

class Chalk::Bootstrap::Semiring::TypeInferenceActions {

    # Helper: Get rightmost type from Context tree (for wrapper rules)
    my $_get_rightmost_type;
    $_get_rightmost_type = sub($ctx) {
        return undef unless defined $ctx;
        my $focus = $ctx->extract();
        if (defined $focus && exists $focus->{type}) {
            return $focus->{type};
        }
        # Walk children right-to-left
        my @children = $ctx->children()->@*;
        for my $child (reverse @children) {
            my $t = $_get_rightmost_type->($child);
            return $t if defined $t;
        }
        return undef;
    };

    # Helper: Get call_symbol from Context tree (for CallExpression)
    my $_get_call_symbol;
    $_get_call_symbol = sub($ctx) {
        return undef unless defined $ctx;
        my $focus = $ctx->extract();
        if (defined $focus) {
            # Focused node (leaf): check for call_symbol and stop
            return $focus->{call_symbol};
        }
        # Unfocused multiply node: recurse into children
        for my $child ($ctx->children()->@*) {
            my $found = $_get_call_symbol->($child);
            return $found if defined $found;
        }
        return undef;
    };

    # Helper: Get op_text from Context tree (for operator rules)
    # Follows leaf-finding semantics: stops at focused nodes.
    my $_get_op_text;
    $_get_op_text = sub($ctx) {
        return undef unless defined $ctx;
        my $focus = $ctx->extract();
        if (defined $focus) {
            return $focus->{op_text};
        }
        for my $child ($ctx->children()->@*) {
            my $found = $_get_op_text->($child);
            return $found if defined $found;
        }
        return undef;
    };

    # Wrapper rules: passthrough child's type

    method Atom($ctx) {
        my $child_type = $_get_rightmost_type->($ctx);
        return { valid => true, ($child_type ? (type => $child_type) : ()) };
    }

    method Expression($ctx) {
        my $child_type = $_get_rightmost_type->($ctx);
        return { valid => true, ($child_type ? (type => $child_type) : ()) };
    }

    method PostfixExpression($ctx) {
        my $child_type = $_get_rightmost_type->($ctx);
        return { valid => true, ($child_type ? (type => $child_type) : ()) };
    }

    # Rich rules: compute type from operator/signature

    method BinaryExpression($ctx) {
        my $op = $_get_op_text->($ctx);
        my $result_type;
        if (defined $op) {
            my $sig = Chalk::Grammar::Perl::TypeLibrary::get_binary_op($op);
            if ($sig && $sig->{result} ne 'Any') {
                $result_type = $sig->{result};
            }
            # result 'Any' → leave type undef (unknown)
        } else {
            # No op_text: preserve child type (intermediate completion)
            $result_type = $_get_rightmost_type->($ctx);
        }
        return { valid => true, ($result_type ? (type => $result_type) : ()) };
    }

    method UnaryExpression($ctx) {
        my $op = $_get_op_text->($ctx);
        my $result_type;
        if (defined $op) {
            my $sig = Chalk::Grammar::Perl::TypeLibrary::get_unary_op($op);
            $result_type = $sig->{result} if $sig;
        }
        return { valid => true, ($result_type ? (type => $result_type) : ()) };
    }

    # Helper: Get list_arity from Context tree
    my $_get_list_arity;
    $_get_list_arity = sub($ctx) {
        return undef unless defined $ctx;
        my $focus = $ctx->extract();
        if (defined $focus) {
            return $focus->{list_arity};
        }
        for my $child ($ctx->children()->@*) {
            my $found = $_get_list_arity->($child);
            return $found if defined $found;
        }
        return undef;
    };

    # Helper: Get item_types from Context tree
    my $_get_item_types;
    $_get_item_types = sub($ctx) {
        return undef unless defined $ctx;
        my $focus = $ctx->extract();
        if (defined $focus) {
            return $focus->{item_types};
        }
        for my $child ($ctx->children()->@*) {
            my $found = $_get_item_types->($child);
            return $found if defined $found;
        }
        return undef;
    };

    # Helper: Search for item_types in previous ExpressionList children
    my $_get_prev_item_types;
    $_get_prev_item_types = sub($ctx) {
        return undef unless defined $ctx;
        my $focus = $ctx->extract();
        if (defined $focus && exists $focus->{item_types}) {
            return $focus->{item_types};
        }
        for my $child ($ctx->children()->@*) {
            my $found = $_get_prev_item_types->($child);
            return $found if defined $found;
        }
        return undef;
    };

    # ExpressionList: arity/item_types tracking
    # alt 0 = single Expression (arity 1)
    # alt 1 = ExpressionList , Expression (arity = child + 1)
    # alt 2 = ExpressionList => Expression (arity = child + 1)
    # alt 3 = trailing comma (arity preserved)

    method ExpressionList($ctx, $alt_idx = 0) {
        my ($arity, $item_types);
        if ($alt_idx == 0) {
            $arity = 1;
            my $type = $_get_rightmost_type->($ctx);
            # type can be undef for non-typed expressions (e.g. function calls)
            $item_types = [$type];
        } elsif ($alt_idx == 1 || $alt_idx == 2) {
            $arity = ($_get_list_arity->($ctx) // 1) + 1;
            my $prev = $_get_prev_item_types->($ctx) // [];
            my $new_type = $_get_rightmost_type->($ctx);
            $item_types = [$prev->@*, $new_type];
        } else {
            $arity = $_get_list_arity->($ctx);
            $item_types = $_get_item_types->($ctx) // $_get_prev_item_types->($ctx);
        }
        return {
            valid => true,
            ($arity ? (list_arity => $arity) : ()),
            ($item_types ? (item_types => $item_types) : ()),
        };
    }

    # CallExpression: validate builtin signatures, determine return type

    method CallExpression($ctx, $tags, $alt_idx = 0) {
        my $return_type = 'Unknown';
        my $call_sym = $_get_call_symbol->($ctx);
        if ($call_sym) {
            my $sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin($call_sym);
            if ($sig) {
                # Validate per-position argument types if available
                my $item_types = $tags->{item_types};
                if ($item_types) {
                    my $arg_types = $sig->{arg_types};
                    my $sig_offset = ($alt_idx == 2 || $alt_idx == 3) ? 1 : 0;
                    for my $i (0 .. $#$item_types) {
                        my $actual = $item_types->[$i];
                        my $sig_idx = $i + $sig_offset;
                        # Variadic: last arg_type applies to remaining positions
                        my $expected = $arg_types->[$sig_idx] // $arg_types->[-1];
                        if (!Chalk::Grammar::Perl::TypeLibrary::type_satisfies($actual, $expected)) {
                            return undef;  # Reject: type mismatch
                        }
                    }
                }
                # Validate min arity
                my $arity = $tags->{list_arity} // 1;
                $arity += 1 if ($alt_idx == 2 || $alt_idx == 3);
                if ($arity < $sig->{min_arity}) {
                    return undef;  # Reject: too few arguments
                }
                # Set return type from signature
                $return_type = $sig->{return_type};
                $return_type = undef if defined $return_type && $return_type eq 'Any';
            }
        }
        return { valid => true, ($return_type ? (type => $return_type) : ()) };
    }

    # Boundary rules: preserve type, clear call_symbol/op_text

    method ParenExpr($ctx) {
        my $child_type = $_get_rightmost_type->($ctx);
        return {
            valid => true,
            ($child_type ? (type => $child_type) : ()),
        };
    }

    method Block($ctx) {
        my $child_type = $_get_rightmost_type->($ctx);
        return {
            valid => true,
            ($child_type ? (type => $child_type) : ()),
        };
    }

    method Signature($ctx) {
        my $child_type = $_get_rightmost_type->($ctx);
        return {
            valid => true,
            ($child_type ? (type => $child_type) : ()),
        };
    }

    method Attribute($ctx) {
        my $child_type = $_get_rightmost_type->($ctx);
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
        return { valid => true };
    }

    method MethodCall($ctx) {
        return { valid => true };
    }
}
