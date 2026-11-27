our $x = 1; sub c { $x = 3; 3 } my $s = ($x == c()) ? "eq" : "ne"; print "$s\n";
