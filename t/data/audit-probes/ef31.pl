my $ok = open(my $fh, "<", $0); my $l = <$fh>; my $c = close($fh); print length($l) > 0 ? "read" : "empty", " $ok $c\n";
