my ($x, $y) = (1, 2); my $c = 1; ($c ? $x : $y)++; ($c ? $x : $y) .= "z"; print "$x$y\n";
