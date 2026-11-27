my $s = "a1b2"; my @r; while ($s =~ /(\d)/g) { push @r, $1 . pos($s) } print "@r\n";
