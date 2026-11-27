our $x = 1; sub c { $x = 0; 1 } my $s = ($x and c()) ? $x : "n"; print "$s\n";
