# ABOUTME: Semantic semiring for building values during parsing with evaluation contexts
# ABOUTME: Tracks contexts and enables semantic actions via EvalContext comonad

use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;
use Chalk::EvalContext;
use Chalk::Grammar::Chalk::Type::Int;
use Chalk::Grammar::Chalk::Type::Num;
use Chalk::Grammar::Chalk::Type::Str;
use Chalk::Grammar::Chalk::Type::Scalar;
use Chalk::Grammar::Chalk::Type::Array;
use Chalk::Grammar::Chalk::Type::Hash;
use Chalk::Grammar::Chalk::Type::List;
use Chalk::Grammar::Chalk::Type::Any;
use Chalk::IR::Node::Scope;

class Chalk::Semiring::SemanticElement :isa(Chalk::Element) {
    field $value     :param :reader;    # Computed semantic value
    field $context   :param :reader;    # Evaluation context
    field $sppf_node :param = undef;    # Optional SPPF node

    method add( $other, $swap = undef ) {

        # Handle undef or wrong type for $other
        return $self unless defined $other;
        return $self unless ref($other) && $other->can('context');

        # For alternatives (choice), prefer non-zero value
        # If self has value 0 (is add_id), return other
        # Use string comparison to avoid numeric coercion warnings
        if ( !defined($value) || (defined($value) && "$value" eq '0') ) {
            return $other;
        }

       # Prefer elements with evaluated focus (defined) over unevaluated (undef)
       # This handles the case where we update the chart after evaluation
        my $self_focus  = $self->context->focus;
        my $other_focus = $other->context->focus;

        if ( !defined($self_focus) && defined($other_focus) ) {
            return $other;
        }
        if ( defined($self_focus) && !defined($other_focus) ) {
            return $self;
        }

        # For semantic values, prefer the alternative that consumed more input
        # (this handles ambiguous parses - longer parse is more complete)
        # Use parse span (end_pos - start_pos) as primary ranking
        my $self_span  = $self->context->end_pos - $self->context->start_pos;
        my $other_span = $other->context->end_pos - $other->context->start_pos;

        if ($ENV{DEBUG_OVERLOAD}) {
            my $self_rule = $self->context->rule ? $self->context->rule->lhs : 'NORULE';
            my $other_rule = $other->context->rule ? $other->context->rule->lhs : 'NORULE';
            if (($self_rule =~ /ClassDeclaration|UseStatement/ || $other_rule =~ /ClassDeclaration|UseStatement/) && $self_span != $other_span) {
                warn "SEMANTIC.add(): $self_rule (span=$self_span) vs $other_rule (span=$other_span)\n";
            }
        }

        if ( $other_span > $self_span ) {
            if ($ENV{DEBUG_OVERLOAD}) {
                my $self_rule = $self->context->rule ? $self->context->rule->lhs : 'NORULE';
                warn "SEMANTIC.add(): Choosing other (longer span) over $self_rule\n";
            }
            return $other;    # Other consumed more input, prefer it
        }
        if ( $self_span > $other_span ) {
            if ($ENV{DEBUG_OVERLOAD}) {
                my $other_rule = $other->context->rule ? $other->context->rule->lhs : 'NORULE';
                warn "SEMANTIC.add(): Choosing self (longer span) over $other_rule\n";
            }
            return $self;     # Self consumed more input, prefer it
        }

     # If spans are equal, prefer the alternative with better IR structure
     # Special case: For ClassDeclaration, prefer the one with more overload mappings
        if ($ENV{DEBUG_OVERLOAD}) {
            my $self_rule = $self->context->rule ? $self->context->rule->lhs : 'NORULE';
            my $other_rule = $other->context->rule ? $other->context->rule->lhs : 'NORULE';
            if ($self_rule eq 'ClassDeclaration' && $other_rule eq 'ClassDeclaration') {
                my $self_has_focus = defined($self_focus) ? 'YES' : 'NO';
                my $other_has_focus = defined($other_focus) ? 'YES' : 'NO';
                warn "SEMANTIC.add(): ClassDeclaration vs ClassDeclaration - self focus=$self_has_focus, other focus=$other_has_focus\n";

                if (defined($self_focus)) {
                    my $self_blessed = blessed($self_focus) ? blessed($self_focus) : 'NOT BLESSED';
                    my $self_op = ($self_blessed ne 'NOT BLESSED' && $self_focus->can('op')) ? $self_focus->op : 'NO OP';
                    warn "  self focus: blessed=$self_blessed, op=$self_op\n";
                }
                if (defined($other_focus)) {
                    my $other_blessed = blessed($other_focus) ? blessed($other_focus) : 'NOT BLESSED';
                    my $other_op = ($other_blessed ne 'NOT BLESSED' && $other_focus->can('op')) ? $other_focus->op : 'NO OP';
                    warn "  other focus: blessed=$other_blessed, op=$other_op\n";
                }
            }
        }

        my $both_classdef = (defined($self_focus) && blessed($self_focus) && $self_focus->can('op') && $self_focus->op eq 'ClassDef' &&
            defined($other_focus) && blessed($other_focus) && $other_focus->can('op') && $other_focus->op eq 'ClassDef');

        if ($ENV{DEBUG_OVERLOAD} && $self->context->rule && $self->context->rule->lhs eq 'ClassDeclaration' && $other->context->rule && $other->context->rule->lhs eq 'ClassDeclaration') {
            if (defined($self_focus) && blessed($self_focus) && $self_focus->can('op') && $self_focus->op eq 'ClassDef') {
                if (defined($other_focus) && blessed($other_focus) && $other_focus->can('op') && $other_focus->op eq 'ClassDef') {
                    warn "  both_classdef check result: $both_classdef\n";
                }
            }
        }

        if ($both_classdef) {
            my $self_mappings = scalar(keys %{$self_focus->overload_mappings // {}});
            my $other_mappings = scalar(keys %{$other_focus->overload_mappings // {}});

            if ($ENV{DEBUG_OVERLOAD}) {
                warn "SEMANTIC.add(): ClassDef comparison - self has $self_mappings mappings, other has $other_mappings mappings\n";
            }

            if ($ENV{DEBUG_OVERLOAD} && $self_mappings != $other_mappings) {
                warn "  Mappings differ!\n";
            }

            if ($other_mappings > $self_mappings) {
                if ($ENV{DEBUG_OVERLOAD}) {
                    warn "SEMANTIC.add(): Choosing other ClassDef (more overload mappings)\n";
                }
                return $other;
            }
            if ($self_mappings > $other_mappings) {
                if ($ENV{DEBUG_OVERLOAD}) {
                    warn "SEMANTIC.add(): Choosing self ClassDef (more overload mappings)\n";
                }
                return $self;
            }
        }

     # If spans are equal, look at children's rightmost position to prefer longer internal matches
     # This handles the case where outer structures have equal spans (ending at closing brace)
     # but different internal parsing (UseStatement ending at 166 vs 241)
        my $self_rule = $self->context->rule ? $self->context->rule->lhs : '';
        my $other_rule = $other->context->rule ? $other->context->rule->lhs : '';

        # Only apply this for rules that can contain varying-length children
        if ($self_rule && $self_rule eq $other_rule && $self_rule eq 'StatementList') {
            my $self_children_count = scalar(@{$self->context->children});
            my $other_children_count = scalar(@{$other->context->children});

            # Only compare if at least one has children
            if ($self_children_count > 0 || $other_children_count > 0) {
                if ($ENV{DEBUG_OVERLOAD}) {
                    warn "SEMANTIC.add(): Checking $self_rule children for max end position\n";
                    warn "  self has $self_children_count children, other has $other_children_count children\n";
                }

                # Find the rightmost (latest ending) child in each alternative
                my $self_max_end = $self->context->start_pos;  # Default to start if no children
                for my $i (0 .. $#{$self->context->children}) {
                    my $child = $self->context->children->[$i];
                    if ($ENV{DEBUG_OVERLOAD} && $self_children_count <= 5) {
                        my $type = ref($child) || 'SCALAR';
                        my $end = ($child && $child->can('end_pos')) ? $child->end_pos : 'N/A';
                        warn "  self child[$i]: type=$type, end=$end\n";
                    }
                    if ($child && $child->can('end_pos')) {
                        my $end = $child->end_pos;
                        $self_max_end = $end if $end > $self_max_end;
                    }
                }

                my $other_max_end = $other->context->start_pos;  # Default to start if no children
                for my $i (0 .. $#{$other->context->children}) {
                    my $child = $other->context->children->[$i];
                    if ($ENV{DEBUG_OVERLOAD} && $other_children_count <= 5) {
                        my $type = ref($child) || 'SCALAR';
                        my $end = ($child && $child->can('end_pos')) ? $child->end_pos : 'N/A';
                        warn "  other child[$i]: type=$type, end=$end\n";
                    }
                    if ($child && $child->can('end_pos')) {
                        my $end = $child->end_pos;
                        $other_max_end = $end if $end > $other_max_end;
                    }
                }

                if ($ENV{DEBUG_OVERLOAD} && $self_max_end != $other_max_end) {
                    warn "SEMANTIC.add(): $self_rule - self max child end=$self_max_end, other max=$other_max_end\n";
                }

                if ($other_max_end > $self_max_end) {
                    if ($ENV{DEBUG_OVERLOAD}) {
                        warn "SEMANTIC.add(): Choosing other $self_rule (child extends further)\n";
                    }
                    return $other;
                }
                if ($self_max_end > $other_max_end) {
                    if ($ENV{DEBUG_OVERLOAD}) {
                        warn "SEMANTIC.add(): Choosing self $self_rule (child extends further)\n";
                    }
                    return $self;
                }
            }
        }

     # If spans are equal, prefer the alternative with more children
     # (handles cases where both consumed same input but one has more structure)
        my $self_children  = scalar( @{ $self->context->children } );
        my $other_children = scalar( @{ $other->context->children } );

        # DEBUG: Log all equal-span disambiguations
        if ($ENV{DEBUG_STMTLIST_DISAMBIG}) {
            warn "[DISAMBIG] $self_rule vs $other_rule: self=$self_children children, other=$other_children children\n";

            if ($self_rule eq 'StatementList' && $other_rule eq 'StatementList') {
                my $self_stmts = ref($self_focus) eq 'ARRAY' ? scalar($self_focus->@*) : '?';
                my $other_stmts = ref($other_focus) eq 'ARRAY' ? scalar($other_focus->@*) : '?';
                warn "[DISAMBIG]   StatementList: self=$self_stmts stmts vs other=$other_stmts stmts\n";
            }
        }

        if ( $other_children > $self_children ) {
            return $other;
        }

        # Otherwise prefer self (first alternative)
        return $self;
    }

    method multiply( $other, $swap = undef ) {

        # Handle undef or wrong type for $other
        return $self unless defined $other;
        return $self unless ref($other) && $other->can('context');

       # For sequences, append other's context to self's children
       # This builds up the children list as we advance the dot through the rule
        my @new_children = ( @{ $self->context->children }, $other->context );

    # Type propagation: keep the type from self's context (the rule being built)
        my $combined_ctx = Chalk::EvalContext->new(
            focus     => undef,                       # Not yet evaluated
            children  => \@new_children,
            start_pos => $self->context->start_pos,
            end_pos   => $other->context->end_pos,
            env       => $self->context->env,
            grammar   => $self->context->grammar,
            rule      => $self->context->rule,
            type      => $self->context->type,        # Propagate type from rule
            metadata_element => $self->context->metadata_element  # Propagate metadata
        );

        return Chalk::Semiring::SemanticElement->new(
            value     => 1,                           # Success value
            context   => $combined_ctx,
            sppf_node => $sppf_node
        );
    }

    method equals( $other, $swap = undef ) {
        return 0 unless defined $other;
        return 0 unless ref($other) eq ref($self);

        # Use refaddr for reference equality to avoid recursion
        # For semantic semiring, we want elements to be considered non-equal
        # to add_id unless they are literally the same object
        return refaddr($self) == refaddr($other) ? 1 : 0;
    }

    method score() {

        # Semantic semiring doesn't use numeric scores
        return 1;
    }

    method to_string(@args) {

    # Return value (0 for add_id, 1 for others) for Parser's numeric comparisons
        return defined($value) ? "$value" : '1';
    }

    # Convenience method to extract focus from context
    # Delegates to context->extract() for comonad-style extraction
    method extract() {
        return $context->extract if defined $context;
        return undef;
    }
}

class Chalk::Semiring::Semantic :isa(Chalk::Semiring) {
    field $env            :param = {};
    field $grammar        :param :reader;
    field $shared_context :param :reader = undef;
    field $type_env       :param :reader =
      {};    # Maps variable names to Chalk::Type objects
    field $input_text     :reader :writer = undef;    # Full input being parsed (for validation)

    field $mul_id :reader = Chalk::Semiring::SemanticElement->new(
        value   => 1,                         # mul_id has value 1
        context => Chalk::EvalContext->new(
            focus     => undef,
            children  => [],
            start_pos => 0,
            end_pos   => 0,
            env       => $env,
            grammar   => $grammar,
            rule      => undef,
            metadata_element => undef        # Identity elements have no metadata
        )
    );
    field $add_id :reader = Chalk::Semiring::SemanticElement->new(
        value   => 0,    # add_id has value 0 (failure/no parse)
        context => Chalk::EvalContext->new(
            focus     => undef,
            children  => [],
            start_pos => 0,
            end_pos   => 0,
            env       => $env,
            grammar   => $grammar,
            rule      => undef,
            metadata_element => undef        # Identity elements have no metadata
        )
    );
    field $_add_id_is_zero :reader = 1;    # Flag to identify add_id

    ADJUST {
        # Initialize scope if not provided - required by Rule classes for variable tracking
        $env->{scope} //= Chalk::IR::Node::Scope->new();
    }

    method init_element_from_rule(
        $rule,
        $start_pos            = 0,
        $end_pos              = 0,
        $parent_derivation_id = undef
      )
    {
        # Infer type from the rule
        my $inferred_type = $self->infer_type_from_rule($rule);

        my $ctx = Chalk::EvalContext->new(
            focus     => undef,
            children  => [],
            start_pos => $start_pos,
            end_pos   => $end_pos,
            env       => $env,
            grammar   => $grammar,
            rule      => $rule,
            type      => $inferred_type,
            metadata_element => undef        # Will be set during on_complete()
        );

        return Chalk::Semiring::SemanticElement->new(
            value   => 1,     # Success value (not add_id which is 0)
            context => $ctx
        );
    }

    method multiply( $x, $y ) {

        # For backward compatibility if called directly
        return $x->multiply($y);
    }

    method plus( $x, $y ) {

        # For backward compatibility if called directly
        return $x->add($y);
    }

    # Infer the type of an expression from its grammar rule
    # TODO put these into the Rule classes themselves
    method infer_type_from_rule($rule) {
        return Chalk::Grammar::Chalk::Type::Any->new() unless defined($rule);

        my $lhs = $rule->lhs;
        my @rhs = @{ $rule->rhs };

        # Literal types - check RHS for terminal patterns
        if ( @rhs == 1 ) {
            my $terminal = $rhs[0];

            # Integer literal
            return Chalk::Grammar::Chalk::Type::Int->new()
              if $terminal eq '%INTEGER%';

            # Float/Number literal
            return Chalk::Grammar::Chalk::Type::Num->new()
              if $terminal eq '%FLOAT%' || $terminal eq '%VERSION%';

            # String literals
            return Chalk::Grammar::Chalk::Type::Str->new()
              if $terminal eq '%SINGLE_QUOTED_STRING%'
              || $terminal eq '%DOUBLE_QUOTED_STRING%';
        }

        # Variable types - infer from sigil in RHS
        if ( $lhs =~ qr/Variable$/ ) {

            # Scalar variable: $ identifier
            if ( @rhs >= 1 && $rhs[0] eq '$' ) {
                return Chalk::Grammar::Chalk::Type::Scalar->new();
            }

            # Array variable: @ identifier
            if ( @rhs >= 1 && $rhs[0] eq '@' ) {
                return Chalk::Grammar::Chalk::Type::Array->new(
                    element_type => Chalk::Grammar::Chalk::Type::Any->new() );
            }

            # Hash variable: % identifier
            if ( @rhs >= 1 && $rhs[0] eq '%' ) {
                return Chalk::Grammar::Chalk::Type::Hash->new(
                    value_type => Chalk::Grammar::Chalk::Type::Any->new() );
            }
        }

        # Operation types - check for operators in RHS
        for my $i ( 0 .. $#rhs ) {
            my $symbol = $rhs[$i];

            # Numeric operations
            if ( $symbol =~ qr/^[+\-*\/]$/ || $symbol eq '**' ) {
                return Chalk::Grammar::Chalk::Type::Num->new();
            }

            # String concatenation
            if ( $symbol eq '.' ) {
                return Chalk::Grammar::Chalk::Type::Str->new();
            }

            # Range operator
            if ( $symbol eq '..' ) {
                return Chalk::Grammar::Chalk::Type::List->new();
            }
        }

        # Type inference by LHS name
        return Chalk::Grammar::Chalk::Type::Int->new()
          if $lhs eq 'Integer' || $lhs eq 'IntegerLiteral';
        return Chalk::Grammar::Chalk::Type::Num->new()
          if $lhs eq 'Number' || $lhs eq 'NumberLiteral';
        return Chalk::Grammar::Chalk::Type::Str->new()
          if $lhs eq 'String'
          || $lhs eq 'StringLiteral'
          || $lhs =~ qr/Quoted/;
        return Chalk::Grammar::Chalk::Type::Array->new(
            element_type => Chalk::Grammar::Chalk::Type::Any->new() )
          if $lhs eq 'ArrayLiteral' || $lhs eq 'List';
        return Chalk::Grammar::Chalk::Type::List->new() if $lhs eq 'Range';

        # Default to Any for unknown constructs
        return Chalk::Grammar::Chalk::Type::Any->new();
    }

    # Override base on_complete() to call semantic actions (evaluate())
    # This maintains polymorphism - Parser calls this uniformly on all semirings
    method on_complete( $completed_item, $completed_element, $metadata_element = undef ) {
        my $ctx = $completed_element->context;

        # Extract type_env from TypeInference element if available in CompositeElement
        # This enables Semantic to access type information during evaluation
        my $env_with_types = $ctx->env;
        if ($metadata_element && $metadata_element->can('element_at')) {
            my $type_elem = $metadata_element->element_at(0);  # TypeInference is first
            if ($type_elem && $type_elem->can('type_env')) {
                my $type_env = $type_elem->type_env;
                if ($type_env && keys $type_env->%*) {
                    # Merge type_env into a copy of env
                    $env_with_types = { %{$ctx->env}, type_env => $type_env };
                }
            }
        }

        # Set metadata_element on context so rule.evaluate() can access precedence metadata
        if ($metadata_element && !$ctx->metadata_element) {
            $ctx = Chalk::EvalContext->new(
                focus     => $ctx->focus,
                children  => $ctx->children,
                start_pos => $ctx->start_pos,
                end_pos   => $ctx->end_pos,
                env       => $env_with_types,
                grammar   => $ctx->grammar,
                rule      => $ctx->rule,
                type      => $ctx->type,
                metadata_element => $metadata_element
            );
        }

        # Evaluate the rule's semantic action if it has one
        my $rule = $ctx->rule;
        if ( $rule && $rule->can('evaluate') ) {
            if ($ENV{DEBUG_OVERLOAD}) {
                my $rule_lhs = $rule->can('lhs') ? $rule->lhs : 'unknown';
                my $num_children = scalar(@{$ctx->children});
                my $start = $ctx->start_pos;
                my $end = $ctx->end_pos;
                my $span = $end - $start;
                warn "SEMANTIC.on_complete(): $rule_lhs with $num_children children, span=$span ($start-$end)\n";
            }

            # Semantic validation: Call rule's validate() method if available and input_text is set
            # This allows rules to reject semantically invalid parses
            my $rule_lhs = $rule->can('lhs') ? $rule->lhs : '';
            if ($rule_lhs eq 'UseStatement') {
                if ($ENV{DEBUG_OVERLOAD}) {
                    my $end_pos = $ctx->end_pos;
                    warn "SEMANTIC VALIDATION: Checking UseStatement at $end_pos (input_text=" . (defined($input_text) ? "SET" : "UNSET") . ", has_validate=" . ($rule->can('validate') ? "YES" : "NO") . ")\n";
                }
                if ($input_text && $rule->can('validate')) {
                    my $end_pos = $ctx->end_pos;
                    my $is_valid = $rule->validate($self, $ctx, $input_text);
                    if (!$is_valid) {
                        if ($ENV{DEBUG_OVERLOAD}) {
                            warn "SEMANTIC VALIDATION: UseStatement at $end_pos failed validation (ExpressionList incomplete), rejecting parse\n";
                        }
                        return $add_id;
                    } else {
                        if ($ENV{DEBUG_OVERLOAD}) {
                            warn "SEMANTIC VALIDATION: UseStatement at $end_pos PASSED validation\n";
                        }
                    }
                }
            }

            my $result;
            try {
                $result = $rule->evaluate($ctx);
            } catch ($e) {
                # Semantic action failed - return add_id to signal parse failure
                # This allows the parser to backtrack and try other alternatives
                warn "[SEMANTIC] evaluate() failed: $e" if $ENV{CHALK_DEBUG_SEMANTIC};
                if ($ENV{DEBUG_OVERLOAD}) {
                    my $rule_lhs = $rule->can('lhs') ? $rule->lhs : 'unknown';
                    warn "SEMANTIC.on_complete(): $rule_lhs evaluation FAILED, returning add_id\n";
                }
                return $add_id;
            }

            # Set the focus to the evaluated result
            $ctx = Chalk::EvalContext->new(
                focus     => $result,
                children  => $ctx->children,
                start_pos => $ctx->start_pos,
                end_pos   => $ctx->end_pos,
                env       => $ctx->env,
                grammar   => $ctx->grammar,
                rule      => $ctx->rule,
                metadata_element => $metadata_element  # Pass metadata from SPPF/Precedence
            );

            # Update the completed element with evaluated context
            $completed_element = Chalk::Semiring::SemanticElement->new(
                value   => 1,
                context => $ctx
            );
        }

        return $completed_element;
    }

    # Override base on_scan() to accumulate terminal values
    # This maintains polymorphism - Parser calls this uniformly on all semirings
    method on_scan( $item, $element, $pos, $matched_value, $pattern_name = undef ) {
        my $match_length = length($matched_value);

        # Create a terminal element with the matched value as focus
        my $terminal_ctx = Chalk::EvalContext->new(
            focus     => $matched_value,
            children  => [],
            start_pos => $pos,
            end_pos   => $pos + $match_length,
            env       => $element->context->env,
            grammar   => $element->context->grammar,
            rule      => $item->rule,
            type      => $element->context->type,
            metadata_element => $element->context->metadata_element  # Propagate metadata
        );

        my $terminal_element = Chalk::Semiring::SemanticElement->new(
            value   => 1,
            context => $terminal_ctx
        );

        # Multiply to accumulate terminal into children
        return $element->multiply($terminal_element);
    }
}

