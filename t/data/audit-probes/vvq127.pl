my $t = "abc"; my @l = map { $t = "zzz"; $_ } substr($t, 0, 1); print "@l\n";
