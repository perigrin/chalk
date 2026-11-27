my $s="abc"; for (substr($s,1,1)) { $_ = "XY" } print "$s\n";
