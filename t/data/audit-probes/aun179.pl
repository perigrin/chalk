my @a = (5); my $r = \@a; my $y = $a[0]++ + $r->[0]; print "$y @a\n";
