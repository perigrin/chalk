my ($x,$y) = (1,2); sub inc { $_[0]++ } for my $c (0,1) { inc($c ? $x : $y) } print "$x$y\n";
