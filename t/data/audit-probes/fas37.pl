my $x=1; sub n { $x=2 } my $r = ($x == 1 && n() && $x == 2) ? "y" : "n"; print "$r\n";
