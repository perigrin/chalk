our $x=1; sub n { $x=7; 0 } my $v = $x == 1 ? n() + $x : -1; print "$v\n";
