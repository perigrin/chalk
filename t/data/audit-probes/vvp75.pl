my %h = (-a=>1); sub f { $h{"-a"} = 5; $_[0] } print f($h{-a}), "\n";
