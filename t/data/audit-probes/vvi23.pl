my $s = "abc"; my $t = lc(uc $s) . ucfirst($s) . lcfirst(uc $s); print "$s$t\n";
