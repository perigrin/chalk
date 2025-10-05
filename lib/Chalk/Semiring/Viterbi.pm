# ABOUTME: Viterbi semiring for tracking best parse scores and paths
# ABOUTME: Provides probabilistic scoring without SPPF forest complexity
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;

class Chalk::Semiring::ViterbiElement :isa(Chalk::Element) {
    field $score :param :reader;
    field $path  :param :reader;

    method add( $other, $swap = undef ) {
        # Viterbi max: choose path with higher score (less negative in log space)
        return $score > $other->score ? $self : $other;
    }

    method multiply( $other, $swap = undef ) {
        # Sequence: add scores in log space, concatenate paths
        return Chalk::Semiring::ViterbiElement->new(
            score => $score + $other->score,
            path  => [ $path->@*, $other->path->@* ]
        );
    }

    method equals( $other, $swap = undef ) {
        return 0 unless ref($other) eq ref($self);
        return $score == $other->score
            && join(',', $path->@*) eq join(',', $other->path->@*);
    }

    method score() {
        return $score;
    }

    method to_string(@) {
        return sprintf('%.4f[%s]', exp($score), join(',', $path->@*));
    }

    method probability() {
        return exp($score);
    }
}

class Chalk::Semiring::Viterbi :isa(Chalk::Semiring) {
    # Identity elements
    field $mul_id :reader = Chalk::Semiring::ViterbiElement->new(
        score => 0,        # log(1) = 0
        path  => ['ε']
    );

    field $add_id :reader = Chalk::Semiring::ViterbiElement->new(
        score => -1e10,    # Very negative (essentially -infinity)
        path  => []
    );

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0) {
        # Viterbi semiring doesn't track positions
        return Chalk::Semiring::ViterbiElement->new(
            score => log($rule->probability),
            path  => [$rule]
        );
    }

    method multiply($x, $y) {
        # For backward compatibility if called directly
        return $x->multiply($y);
    }

    method plus($x, $y) {
        # For backward compatibility if called directly
        return $x->add($y);
    }
}

1;
