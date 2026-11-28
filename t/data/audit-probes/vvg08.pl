my $x = 1; my $y = 2; my @r = (\$x, \$y); ${$r[$_]} += 10 for 0..1; print "$x$y\n";
