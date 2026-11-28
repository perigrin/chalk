our $x = 1; our $t; sub c { $t = 3; 2 } my $s = ($t = $x) . c(); print "$s\n";
