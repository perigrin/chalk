my $t = "abc"; for my $e (substr($t, 0, 1)) { $t = "zzz"; print $e } print "\n";
