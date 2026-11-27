our $x = 1; sub c { $x = 0; 1 } my $s = ($x && c() && $x) ? "t" : "f"; print "$s\n";
