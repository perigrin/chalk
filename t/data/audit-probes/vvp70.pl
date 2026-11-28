my %h = (ab=>1); use constant K => "ab"; sub f { $h{+K} = 5; $_[0] } print f($h{ab}), "\n";
