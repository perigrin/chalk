my $t = "abc"; sub rd { "$_[0]" } my $s = rd(substr($t, 0, 1)); $t = "zzz"; print "$s\n";
