# ABOUTME: Chalk/Perl-specific semantic validation rules for parsing
# ABOUTME: Encapsulates grammar-specific constraints like postfix conditional restrictions
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;

class Chalk::Grammar::Chalk::SemanticRules {
    # Validate a packed SPPF node for semantic correctness
    # Returns 1 if valid, 0 if invalid
    method validate($packed) {
        my $rule = $packed->rule;
        return 1 unless $rule;  # Non-rule nodes valid by default

        # VALIDATION: Statement -> Statement WS_OPT ConditionalKeyword WS_OPT Expression
        # This is the postfix conditional modifier rule
        # It should NOT apply when the base Statement is already a block-form conditional
        if ($rule->lhs eq 'Statement' && $self->_is_postfix_conditional_rule($rule)) {
            return $self->_validate_postfix_conditional($packed);
        }

        # Add more Chalk/Perl-specific validation rules here as needed:
        # - No 'my' in expression context
        # - Method call syntax validation
        # - Package name validation
        # - etc.

        return 1;  # Default: valid
    }

    method _is_postfix_conditional_rule($rule) {
        # Check if this is: Statement -> Statement WS_OPT ConditionalKeyword WS_OPT Expression
        my $rhs = $rule->rhs;
        return 0 unless $rhs && ref($rhs) eq 'ARRAY';
        return 0 unless scalar($rhs->@*) == 5;

        return ($rhs->[0] eq 'Statement' &&
                $rhs->[1] eq 'WS_OPT' &&
                $rhs->[2] eq 'ConditionalKeyword' &&
                $rhs->[3] eq 'WS_OPT' &&
                $rhs->[4] eq 'Expression');
    }

    method _validate_postfix_conditional($packed) {
        my @children = $packed->children;
        return 1 unless @children;

        # First child should be the base Statement
        my $base_stmt_node = $children[0];
        return 1 unless $base_stmt_node && $base_stmt_node->isa('Chalk::ParseForest::SymbolNode');

        # Check if base statement is a Block (which includes ConditionalStatement)
        # If it is, this postfix application is INVALID
        return !$self->_statement_is_block_form($base_stmt_node);
    }

    method _statement_is_block_form($stmt_node) {
        # Check if Statement -> Block
        my @packed = $stmt_node->packed_nodes;
        return 0 unless @packed;

        for my $packed (@packed) {
            my $rule = $packed->rule;
            next unless $rule;

            # Statement -> Block rule
            if ($rule->lhs eq 'Statement' && $self->_is_block_rule($rule)) {
                return 1;  # Yes, this is a block-form statement
            }
        }

        return 0;  # Not a block-form statement
    }

    method _is_block_rule($rule) {
        my $rhs = $rule->rhs;
        return 0 unless $rhs && ref($rhs) eq 'ARRAY';
        return 0 unless scalar($rhs->@*) == 1;
        return $rhs->[0] eq 'Block';
    }
}

1;
