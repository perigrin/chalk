my %memo; sub fb { my $n=shift; $memo{$n} //= $n<2 ? $n : fb($n-1)+fb($n-2) } print fb(20), scalar(keys %memo), "\n";
