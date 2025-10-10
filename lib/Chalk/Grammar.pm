# ABOUTME: Grammar and rule definitions for Chalk parser
# ABOUTME: Provides GrammarRule and Grammar classes for defining parsing grammars
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;

class Chalk::GrammarRule {

    # Supports both exact token matching and lexeme/regex patterns for terminals
    # Use parse() for pre-tokenized input, parse_string() for lexeme matching
    #
    # TODO: Consider matrix-based Earley parsing optimization
    # See: https://medium.com/@celine.y.lee/fast-earley-parsing-2216fb0909a3
    # Matrix operations could optimize prediction/completion phases while
    # lexemes handle terminal matching independently
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
        return $nullable = 1 if @$rhs == 0;

        # All symbols in RHS must be nullable
        return $nullable = 1 if all {
            my @rules = $grammar->rules_for($_);

            # Terminals (no rules) are not nullable
            return 0 unless @rules;

            # In cycle, assume not nullable
            return 0 if $seen->{$_};

            # Check if this symbol is nullable via any of its rules
            $seen->{$_} = 1;
            return 0 unless any { $_->is_nullable( $grammar, $seen ) } @rules;
        } @$rhs;

        return $nullable = 0;
    }

    method to_string(@) {
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
}

class Chalk::Grammar {
    field $rules        :param :reader;
    field $start_symbol :param :reader;
    field %nullable_cache;

    ADJUST {
        for my $s ( keys(%$rules) ) {
            $self->is_nullable($s);
        }
    }

    my sub new_rule( $lhs, $rhs, $probability = 1.0 ) {
        $probability ||= 0.1;
        return Chalk::GrammarRule->new(
            lhs         => $lhs,
            rhs         => $rhs,
            probability => $probability
        );
    }

    my sub insert ( $items, @list ) {
        return [ ( map { $_, @$items } @list[ 0 .. $#list - 1 ] ), $list[-1] ];
    }

    sub build_grammar( $class, @args ) {
        my $auto_insert;
        my @rules;

        # Support both calling conventions:
        # 1. Named parameters: build_grammar(auto_insert => [...], rules => [...])
        # 2. Positional: build_grammar($auto_insert, @rules) or build_grammar(@rules)

        if (@args > 0 && !ref($args[0]) && ($args[0] eq 'auto_insert' || $args[0] eq 'rules')) {
            # Named parameter format
            my %params = @args;
            $auto_insert = $params{auto_insert} // [];
            @rules = @{ $params{rules} // [] };
        } else {
            # Positional format
            my $first = shift(@args) // [];

            # Auto-detection: If $first looks like a rule (2+ element arrayref where 2nd element is arrayref),
            # then it's the first rule, not auto_insert.
            # Rules are: [ 'LHS', [ 'RHS', 'items' ], optional_probability ]
            # Auto-insert arrays are: [ 'SYMBOL' ] or [ 'SYMBOL1', 'SYMBOL2' ] (strings, not arrayrefs)
            if ( ref($first) eq 'ARRAY' && @$first >= 2 && ref($first->[1]) eq 'ARRAY' ) {
                # First arg is a rule, not auto_insert
                $auto_insert = [];
                @rules = ($first, @args);
            } else {
                # First arg is auto_insert
                $auto_insert = $first;
                @rules = @args;
            }
        }

        my %rules_hash = ();
        for my $r (@rules) {
            my ( $lhs, $rhs ) = @$r;
            if ( @$auto_insert && @$rhs > 1 ) {
                $r->[1] = insert( $auto_insert, @$rhs );
            }
            push( @{ $rules_hash{$lhs} //= [] }, new_rule(@$r) );
        }
        return Chalk::Grammar->new( rules => \%rules_hash, start_symbol => $rules[0]->[0] );
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

    method to_string(@) {
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
