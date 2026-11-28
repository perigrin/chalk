our %a = (k=>1); *b = \%a; our %b; delete $b{k}; print scalar(keys %a), "\n";
