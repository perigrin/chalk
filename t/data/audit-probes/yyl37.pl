my $s = "aaa bbb"; my $c = () = $s =~ /a/g; my $first = $s =~ /(b+)/ ? $1 : ""; my ($pre) = $s =~ /^(\w+)/; my $cnt = $s =~ s/b/B/g; print "$c$first$pre$cnt$s\n";
