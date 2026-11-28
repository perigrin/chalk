our $x = 1; our $y = 0; sub c { $x = 3; 2 } my $s = ($y || $x) . c(); print "$s\n";
