my %h = (ab=>1); sub f { @h{qw(ab)} = (5); $_[0] } print f($h{ab}), "\n";
