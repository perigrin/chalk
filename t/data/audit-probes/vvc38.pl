our $x = 1; my $y = 2; *x = \$y if $y > 5; $x = 5; print "$x$y\n";
