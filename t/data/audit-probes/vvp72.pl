my %h = (ab=>1); use constant K => "ab"; sub f { $h{ab} = 5; $_[0] } print f($h{+K}), "\n";
