my ($x,$y) = (1,2); my $c = 1; ($c ? $x : $y) .= "a"; $c = 0; ($c ? $x : $y) .= "b"; print "$x$y\n";
