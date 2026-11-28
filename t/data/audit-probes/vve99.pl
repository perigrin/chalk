my %h = (k=>1); sub f { @h{qw(k)} = (5); $_[0] } print f($h{k}), "\n";
