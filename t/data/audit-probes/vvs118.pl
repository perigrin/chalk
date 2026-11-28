my $s = "abc"; $s =~ /(a)/; my $t = "xy" =~ s/(x)/<$1>/r; print "$t$1\n";
