our $x=1; sub n { $x=7; 1 } my $v = (n() && $x) + $x; print "$v\n";
