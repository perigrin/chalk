my $s = "aabb"; my $t = $s =~ s/(a+)/<$1>/r; print "$t$1\n";
