my $t = "abc"; my $s = substr($t, 0, 1) . ($t = "zzz"); print "$s\n";
