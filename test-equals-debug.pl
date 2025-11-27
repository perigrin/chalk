#!/usr/bin/env perl
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use lib 'lib';
use Chalk::Semiring::Precedence;
use Chalk::Semiring::Boolean;

# Test Precedence equals
my @perl_precedence_table = (
    { assoc => 'left', ops => ['+', '-'] },
);

my $precedence_sr = Chalk::Semiring::Precedence->new(
    precedence_table => \@perl_precedence_table
);

my $elem1 = Chalk::Semiring::PrecedenceElement->new(
    valid => 1,
    operator => '+',
    precedence_level => 0,
    associativity => 'left',
    operator_index => {}
);

my $elem2 = Chalk::Semiring::PrecedenceElement->new(
    valid => 1,
    operator => '-',
    precedence_level => 0,
    associativity => 'left',
    operator_index => {}
);

my $elem3 = Chalk::Semiring::PrecedenceElement->new(
    valid => 1,
    operator => '+',
    precedence_level => 0,
    associativity => 'left',
    operator_index => {}
);

say "Testing Precedence equals()";
say "elem1 == elem2: ", $elem1->equals($elem2) ? "TRUE" : "FALSE";
say "elem1 == elem3: ", $elem1->equals($elem3) ? "TRUE" : "FALSE";

# Test Boolean equals
my $bool_sr = Chalk::Semiring::Boolean->new();

my $bool1 = Chalk::Semiring::BooleanElement->new(value => 1);
my $bool2 = Chalk::Semiring::BooleanElement->new(value => 0);
my $bool3 = Chalk::Semiring::BooleanElement->new(value => 1);

say "\nTesting Boolean equals()";
say "bool1 == bool2: ", $bool1->equals($bool2) ? "TRUE" : "FALSE";
say "bool1 == bool3: ", $bool1->equals($bool3) ? "TRUE" : "FALSE";
say "bool2 == add_id: ", $bool2->equals($bool_sr->add_id) ? "TRUE" : "FALSE";
