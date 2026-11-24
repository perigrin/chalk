our $x=1; sub n { $x=7; 0 } my $v = $x * 10 + n() + $x; print "$v\n";
