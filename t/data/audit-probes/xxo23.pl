our %g = (a=>1,b=>2); { delete local @g{qw(a b)}; print scalar(keys %g) } print scalar(keys %g), "\n";
