my $s = "ab"; my $n = ($s =~ tr/a/x/); my %h = ($s => $n); print join(",", %h), "\n";
