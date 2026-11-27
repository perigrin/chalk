our $x = 1; sub c { $x = 3; 2 } my $s = (1 ? $x : 0) . c(); print "$s\n";
