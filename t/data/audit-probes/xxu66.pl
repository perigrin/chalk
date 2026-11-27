our $x = 1; sub c { $x = 3; 2 } my $n = () = ($x, c()); my ($f) = ($x, c()); print "$n$f\n";
