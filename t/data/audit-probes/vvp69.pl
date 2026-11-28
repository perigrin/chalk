my %h = (ab=>1); sub f { $h{lc "AB"} = 5; $_[0] } print f($h{ab}), "\n";
