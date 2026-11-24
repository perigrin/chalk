"ab"=~/(a)/; my $t = do { "xy"=~/(y)/; $1 }; print "$t$1\n";
