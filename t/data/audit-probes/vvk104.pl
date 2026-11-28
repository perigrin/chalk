my $x = 5; my $r = $x < 3 ? "s" : $x < 10 ? "m" : "l"; unless ($x == 5) { $r = "n" } else { $r .= "!" } print "$r\n";
