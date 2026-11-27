our $x = 1; sub c { $x = 3; 2 } $x = $x + c(); print "$x\n";
