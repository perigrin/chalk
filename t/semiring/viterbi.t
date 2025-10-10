#!/usr/bin/env perl
# ABOUTME: Test pure Viterbi semiring implementation
# ABOUTME: Verifies scoring and path tracking without SPPF complexity
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";
use experimental qw(defer);
defer { done_testing() }

use Chalk::Base;
use Chalk::Semiring::Viterbi;

subtest 'ViterbiElement basic properties' => sub {
    my $elem = Chalk::Semiring::ViterbiElement->new(
        score => -0.5,
        path  => ['rule1']
    );

    ok $elem, 'ViterbiElement created';
    is $elem->score, -0.5, 'Score accessor works';
    is $elem->path, ['rule1'], 'Path accessor works';
};

subtest 'ViterbiElement multiplication (sequence)' => sub {
    my $elem1 = Chalk::Semiring::ViterbiElement->new(
        score => -0.5,
        path  => ['rule1']
    );

    my $elem2 = Chalk::Semiring::ViterbiElement->new(
        score => -0.3,
        path  => ['rule2']
    );

    my $result = $elem1->multiply($elem2);

    ok $result, 'Multiplication succeeds';
    is $result->score, -0.8, 'Scores add in log space';
    is $result->path, ['rule1', 'rule2'], 'Paths concatenate';
};

subtest 'ViterbiElement addition (choice - max)' => sub {
    my $elem1 = Chalk::Semiring::ViterbiElement->new(
        score => -0.5,
        path  => ['rule1']
    );

    my $elem2 = Chalk::Semiring::ViterbiElement->new(
        score => -0.3,
        path  => ['rule2']
    );

    my $result = $elem1->add($elem2);

    ok $result, 'Addition succeeds';
    is $result->score, -0.3, 'Returns higher score (less negative)';
    is $result->path, ['rule2'], 'Returns path of better score';
};

subtest 'ViterbiElement equality' => sub {
    my $elem1 = Chalk::Semiring::ViterbiElement->new(
        score => -0.5,
        path  => ['rule1']
    );

    my $elem2 = Chalk::Semiring::ViterbiElement->new(
        score => -0.5,
        path  => ['rule1']
    );

    my $elem3 = Chalk::Semiring::ViterbiElement->new(
        score => -0.3,
        path  => ['rule1']
    );

    ok $elem1->equals($elem2), 'Equal elements are equal';
    ok !$elem1->equals($elem3), 'Different scores not equal';
};

subtest 'ViterbiElement to_string' => sub {
    my $elem = Chalk::Semiring::ViterbiElement->new(
        score => log(0.5),
        path  => ['rule1', 'rule2']
    );

    my $str = $elem->to_string;
    ok $str, 'to_string produces output';
    like $str, qr/0\.5/, 'Shows probability (exp of score)';
    like $str, qr/rule1/, 'Shows path info';
};

subtest 'ViterbiElement probability method' => sub {
    my $elem = Chalk::Semiring::ViterbiElement->new(
        score => log(0.5),
        path  => ['rule1']
    );

    my $prob = $elem->probability;
    ok abs($prob - 0.5) < 0.0001, 'Probability is exp(score)';
};

subtest 'ViterbiSemiring identity elements' => sub {
    my $semiring = Chalk::Semiring::Viterbi->new();

    ok $semiring, 'Viterbi semiring created';
    ok $semiring->mul_id, 'Has multiplicative identity';
    ok $semiring->add_id, 'Has additive identity';

    is $semiring->mul_id->score, 0, 'Multiplicative identity has score 0 (log(1))';
    is $semiring->add_id->score, -1e10, 'Additive identity has very negative score';
};

subtest 'ViterbiSemiring multiplicative identity behavior' => sub {
    my $semiring = Chalk::Semiring::Viterbi->new();
    my $elem = Chalk::Semiring::ViterbiElement->new(
        score => -0.5,
        path  => ['rule1']
    );

    my $result = $elem->multiply($semiring->mul_id);

    is $result->score, -0.5, 'Multiplying by identity preserves score';
    is $result->path, ['rule1', 'ε'], 'Identity adds epsilon to path';
};

subtest 'ViterbiSemiring additive identity behavior' => sub {
    my $semiring = Chalk::Semiring::Viterbi->new();
    my $elem = Chalk::Semiring::ViterbiElement->new(
        score => -0.5,
        path  => ['rule1']
    );

    my $result = $elem->add($semiring->add_id);

    is $result->score, -0.5, 'Adding identity returns element (better score)';
    is $result->path, ['rule1'], 'Returns original element path';
};

subtest 'ViterbiSemiring operator overloading' => sub {
    my $elem1 = Chalk::Semiring::ViterbiElement->new(
        score => -0.5,
        path  => ['rule1']
    );

    my $elem2 = Chalk::Semiring::ViterbiElement->new(
        score => -0.3,
        path  => ['rule2']
    );

    my $mult = $elem1 * $elem2;
    is $mult->score, -0.8, 'Operator * works';

    my $add = $elem1 + $elem2;
    is $add->score, -0.3, 'Operator + works';

    ok($elem1 == $elem1, 'Operator == works');
};
