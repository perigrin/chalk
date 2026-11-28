our $x = 1; our $y = 1; sub c { $x = 3; 2 } my $s = ($y ? $x : 0) . c(); print "$s\n";
