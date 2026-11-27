my $s = "abc"; (my $t = $s) =~ s/(b)/<$1>/; print "$s$t$1\n";
