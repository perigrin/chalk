my ($a1,$b1); my $c=0; ($c ? $a1 : $b1) //= 7; print defined $a1 ? 1 : 0, "$b1\n";
