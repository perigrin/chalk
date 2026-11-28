my $t = "abc"; sub rd { $t = "zzz"; "$_[0]" } print rd(substr($t, 0, 1)), "\n";
