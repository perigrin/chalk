my $x=3; my $r = do { 1; 2; $x*2 }; my $u = do { if ($x>2) { "big" } else { "small" } }; print "$r$u\n";
