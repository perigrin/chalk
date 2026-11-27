our $x = 1; sub c { $x = 3; 2 } $x .= c() . $x; print "$x\n";
