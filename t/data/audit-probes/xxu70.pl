our $x = 1; sub c { $x = 3; 2 } my $s = ($x || 0) . c(); print "$s\n";
