our $x = 1; sub c { $x = 3; 2 } my $p = $x; my $q = c(); print "$p$q$x\n";
