my %h = (ab=>1); sub f { $h{"ab"} = 5; $_[0] } print f($h{q(ab)}), "\n";
