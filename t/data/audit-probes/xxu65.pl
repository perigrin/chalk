our $x = 1; sub c { $x = 3; 2 } my $s = (c(), $x)[1] . ($x, c())[0]; print "$s\n";
