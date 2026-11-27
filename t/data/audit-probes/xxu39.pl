our $x = 1; sub c { $x = 3; 2 } my $s = ($x < c()) ? "lt" : "ge"; print "$s\n";
