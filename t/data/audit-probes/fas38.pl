my $x=1; sub n { $x=0; 1 } my $r = n() ? $x : 9; print "$r\n";
