our $x = "ab"; sub c { $x = "cd"; 1 } my $s = substr($x, 0, 1) . c(); print "$s\n";
