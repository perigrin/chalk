my $s = "abc"; for (substr($s, 1, 1)) { $_ = "Z" } print "$s\n";
