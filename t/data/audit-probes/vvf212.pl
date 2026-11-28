our $t = "a"; sub c { $t = 3; 2 } my $s = ($t .= "b") . c(); print "$s\n";
