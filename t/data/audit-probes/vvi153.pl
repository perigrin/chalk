my $s = "abc"; my $t = $s; $t = uc $t if $s =~ /b/; $s = lc $s unless $t =~ /b/; print "$s$t\n";
