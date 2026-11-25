my $s = "a1b22c333"; my $t = ""; while ($s =~ /(\d+)/g) { $t .= length($1) . pos($s) . "," } print "$t\n";
