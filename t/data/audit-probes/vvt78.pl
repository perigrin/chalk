sub f { $_[0]++ } my $t = 0; for my $i (1..3) { my %y = (k => $i); f($y{k}); $t += $y{k} } print "$t\n";
