my $v = do { 1; 2 } + do { my $t = 3; $t * 2 }; my @l = do { (1,2) }; print "$v@l\n";
