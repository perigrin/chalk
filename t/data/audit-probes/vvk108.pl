my $x = do { 1; 2; 3 }; my $y = do { my $t = 4; $t * 2 }; my @z = do { (1, 2) }; print "$x$y@z\n";
