my %h = (ab=>1); sub f { %h = (ab => 5); 0 } my $k = 0; print f($k), $h{ab}, "\n";
