my $t = "abc"; sub rd { $t = "zzz"; my $v = shift; $v } print rd(substr($t, 0, 1)), "\n";
