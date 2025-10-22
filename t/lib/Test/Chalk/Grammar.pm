# ABOUTME: Test helper for building Chalk::Grammar objects from rule arrays
# ABOUTME: Provides build_grammar factory method for test code
use 5.42.0;
use experimental qw(class);

class Test::Chalk::Grammar {
    use Chalk::Grammar;

    # Factory method for creating Grammar objects from rule arrays
    # Used by tests to programmatically construct grammars
    # Takes: rules => [[lhs, rhs, probability], ...]
    # Returns: Chalk::Grammar object
    sub build_grammar( $class, %args ) {
        my $rules_array = $args{rules} // [];

        my %rules = ();
        for my $r ( $rules_array->@* ) {
            my ( $lhs, $rhs, $probability ) = $r->@*;
            $probability //= 1.0;
            $probability ||= 0.1;  # Convert 0 to 0.1

            push( @{ $rules{$lhs} //= [] }, Chalk::GrammarRule->new(
                lhs         => $lhs,
                rhs         => $rhs,
                probability => $probability
            ) );
        }
        return Chalk::Grammar->new(
            rules        => \%rules,
            start_symbol => $rules_array->[0]->[0]
        );
    }
}

1;
