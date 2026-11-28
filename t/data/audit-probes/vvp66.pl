my %h = (ab=>1); sub f { $h{"a" . "b"} = 5; $_[0] } print f($h{ab}), "\n";
