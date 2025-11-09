# ABOUTME: Grammar and rule definitions for Chalk parser
# ABOUTME: Provides GrammarRule and Grammar classes for defining parsing grammars
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;

class Chalk::GrammarRule {

    # Supports both exact token matching and lexeme/regex patterns for terminals
    # Use parse() for pre-tokenized input, parse_string() for lexeme matching
    use overload '""' => 'to_string';

    state $next_id = 0;    # auto-incrementing rule ID
    field $id  :reader = $next_id++;
    field $lhs :param :reader;
    field $rhs :param :reader;
    field $probability :param :reader = 1.0;
    field $nullable;

    method is_right_recursive() { $lhs eq $rhs->[-1] }
    method is_left_recursive()  { $lhs eq $rhs->[0] }

    method is_nullable( $grammar, $seen = {} ) {
        return $nullable if defined($nullable);    # memoize nullable

        # Empty production is nullable
        return $nullable = 1 if $rhs->@* == 0;

        # All symbols in RHS must be nullable
        return $nullable = 1 if all {
            my @rules = $grammar->rules_for($_);

            # Terminals (no rules) - check if nullable
            unless (@rules) {

                # For regex terminals, test if they match empty string
                if ( ref($_) eq 'Regexp' ) {
                    return "" =~ $_;
                }

    # String terminals are not nullable (empty string would be in grammar as [])
                return 0;
            }

            # In cycle, assume not nullable
            return 0 if $seen->{$_};

            # Check if this symbol is nullable via any of its rules
            $seen->{$_} = 1;
            return 0 unless any { $_->is_nullable( $grammar, $seen ) } @rules;
        } $rhs->@*;

        return $nullable = 0;
    }

    method to_string(@args) {
        return "($id) $lhs -> " . join( ' ', $rhs->@* );
    }

    method terminal_to_regex($terminal) {
        state %seen;

        # Convert terminal to regex pattern
        # If already a regex, return as-is
        # If string literal, escape and convert to regex
        return $seen{$terminal} //=
          ref($terminal) eq 'Regexp' ? $terminal : qr/\Q$terminal\E/;
    }

    # Default semantic action: die with clear error message
    # All grammar rules that need semantic actions MUST override this method
    # This prevents silent bugs from arrayrefs propagating through IR construction
    method evaluate($context) {
        my $rule = $context->rule;
        my $rule_name = $rule ? $rule->lhs : 'unknown';
        die "Rule '$rule_name' has no evaluate() method - all grammar rules used with semantic evaluation must implement evaluate().\n" .
            "Either create lib/Chalk/Grammar/*/Rule/${rule_name}.pm with an evaluate() method,\n" .
            "or if this rule should just pass through child(0), add a simple pass-through evaluate().\n";
    }
}

class Chalk::Grammar {
    use Chalk::Grammar::BNF;
    use Chalk::Parser;
    use Chalk::Semiring::Semantic;

    field $rules        :param :reader;
    field $start_symbol :param :reader;
    field %nullable_cache;
    field
      %rules_waiting_for; # Pre-computed: which rules can wait for which symbols

    ADJUST {
        for my $s ( keys( $rules->%* ) ) {
            $self->is_nullable($s);
        }

        # Pre-compute which rules can wait for which symbols
        # For each rule A -> α B β, rule A can wait for symbol B
        for my $lhs ( keys( $rules->%* ) ) {
            for my $rule ( $rules->{$lhs}->@* ) {
                my @rhs = $rule->rhs->@*;
                for my $i ( 0 .. $#rhs ) {
                    my $symbol = $rhs[$i];

                    # This rule can have its dot before $symbol
                    $rules_waiting_for{$symbol} //= [];
                    push(
                        $rules_waiting_for{$symbol}->@*,
                        {
                            rule    => $rule,
                            dot_pos => $i,
                        }
                    );
                }
            }
        }
    }

   # Build a Grammar from BNF content with optional start symbol override
   # Production code (app.pl) provides start_symbol; defaults to first nonterminal if not specified
    sub build_from_bnf( $class, $bnf_content, $start_symbol = undef, $grammar_name = undef ) {

        # Parse BNF using hand-coded BNF grammar with semantic actions
        # This parser fully supports all BNF syntax including grammar rules,
        # terminals, nonterminals, pattern definitions, and comments.
        my $bnf         = Chalk::Grammar::BNF->new();
        my $bnf_grammar = $bnf->grammar();

        # Create environment with pattern table for storing %NAME% definitions
        # grammar_name enables automatic loading of Chalk::Grammar::{Name}::Rule::* classes
        my %env = (
            patterns     => {},           # Pattern name => compiled regex
            grammar_name => $grammar_name # For loading custom semantic action classes
        );

        # Create shared context with parse forest for compositional semirings
        use Chalk::ParseForest;
        my %shared_context = (
            forest => Chalk::ParseForest->new()
        );

        my $semiring = Chalk::Semiring::Semantic->new(
            env     => \%env,
            grammar => $bnf_grammar,
            shared_context => \%shared_context
        );

        my $parser = Chalk::Parser->new(
            grammar  => $bnf_grammar,
            semiring => $semiring
        );

        my $result = $parser->parse_string($bnf_content);

        # Extract Grammar object from semantic result
        my $grammar = $result ? $result->context->extract : undef;

        return undef unless $grammar;

     # If start symbol specified and different, create new Grammar with override
        if ( defined($start_symbol) && $grammar->start_symbol ne $start_symbol )
        {
            return Chalk::Grammar->new(
                rules        => $grammar->rules,
                start_symbol => $start_symbol
            );
        }

        return $grammar;
    }

    method start_rule() { return $rules->{$start_symbol}->[0] }

    method rules_for($symbol) {
        return $rules->{$symbol}->@* if exists( $rules->{$symbol} );
        return;
    }

    method is_nonterminal($symbol) {
        return exists( $rules->{$symbol} );
    }

    method is_nullable($symbol) {

        # Check cache first
        return $nullable_cache{$symbol} if exists( $nullable_cache{$symbol} );

       # Compute nullability by checking if any rule for this symbol is nullable
        my $result = 0;
        for my $rule ( $self->rules_for($symbol) ) {
            if ( $rule->is_nullable($self) ) {
                $result = 1;
                last;
            }
        }

        # Cache the result
        $nullable_cache{$symbol} = $result;
        return $result;
    }

    method rules_waiting_for($symbol) {

        # Returns list of { rule, dot_pos } that can wait for this symbol
        return $rules_waiting_for{$symbol}->@*
          if exists( $rules_waiting_for{$symbol} );
        return;
    }

    method to_string(@args) {
        my $grammar = '';
        $grammar .= "Grammar:\n";
        for my $nt ( sort( keys( $rules->%* ) ) ) {
            for my $rule ( $rules->{$nt}->@* ) {
                $grammar .= "  $rule\n";
            }
        }
        $grammar .= "\n";
        return $grammar;
    }
}

1;
