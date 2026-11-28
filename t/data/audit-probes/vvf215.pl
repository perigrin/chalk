our $t = "a"; sub c { $t = "zz"; 2 } my $s = substr($t, 0, 1) . c(); print "$s\n";
