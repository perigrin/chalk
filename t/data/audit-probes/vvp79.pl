my %h = (ab=>1); sub f { my ($k) = keys %h; $h{$k} = 5; $_[0] } print f($h{ab}), "\n";
