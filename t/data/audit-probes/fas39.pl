my $x=5; sub n { $x=0 } my $r = $x ? (n(), $x)[1] : 9; print "$r\n";
