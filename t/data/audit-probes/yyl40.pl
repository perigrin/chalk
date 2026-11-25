my $s = "The Cat"; my @u = $s =~ /([A-Z])/g; my $l = lc $s; my $cnt = ($l =~ tr/a-z//); my $i = index($l, "cat"); $s =~ s/(\w+) (\w+)/$2 $1/; print "@u$cnt$i$s\n";
