our $x = 1; sub c { $x = 3; 2 } my $s = lc($x) . c(); print "$s\n";
