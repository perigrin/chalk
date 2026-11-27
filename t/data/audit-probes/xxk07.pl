my ($x,$y) = (1,2); my $c = 1; my $r = \($c ? $x : $y); $$r = 5; print "$x$y\n";
