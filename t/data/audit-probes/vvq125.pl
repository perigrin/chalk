my $t = "abc"; sub rd { $t = "zzz"; my ($v) = @_; $v } print rd(substr($t, 0, 1)), "\n";
